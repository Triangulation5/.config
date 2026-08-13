#!/usr/bin/env python3
"""Polkit authentication agent for the pill.

Registers with polkitd on the system bus as this login session's
authentication agent, so when any app needs admin rights the prompt lands on
the pill instead of a system dialog. The agent relays the request to the shell
with `qs ipc call polkit prompt ...`; the shell morphs the pill into an
authorize face, and the answer comes back through a file in
`$XDG_RUNTIME_DIR/ricelin-polkit/response` (the password, or the literal
CANCEL).

How the password reaches polkitd (polkit >= 125): it never crosses D-Bus. The
agent spawns the setuid helper `/usr/lib/polkit-1/polkit-agent-helper-1` with
the identity's username, hands it the conversation cookie on stdin, and relays
the PAM conversation over pipes. The helper runs the `polkit-1` PAM stack as
root (so fingerprint and howdy modules in /etc/pam.d/polkit-1 work without this
script knowing anything about them) and on success calls
AuthenticationAgentResponse2 on polkitd itself. The agent holds the
BeginAuthentication D-Bus call open until the helper reports SUCCESS or
FAILURE, then replies; polkitd decides based on whether the helper already
notified it. A CANCEL from the shell (or a CancelAuthentication from polkitd)
kills the helper and replies with the Cancelled error so polkitd records the
conversation as dismissed.

The response file is user-only (XDG_RUNTIME_DIR is mode 0700); the password
lives there for the few milliseconds between the shell writing it and this
process reading it.
"""

import os
import pwd
import subprocess
import sys
import threading

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
BASE = os.path.join(RUNTIME, "ricelin-polkit")
RESP_FILE = os.path.join(BASE, "response")

AGENT_PATH = "/org/ricelin/PolkitAgent"
AUTHORITY_NAME = "org.freedesktop.PolicyKit1"
AUTHORITY_PATH = "/org/freedesktop/PolicyKit1/Authority"
IFACE = "org.freedesktop.PolicyKit1.AuthenticationAgent"
HELPER = "/usr/lib/polkit-1/polkit-agent-helper-1"
POLL_MS = 100


class Agent(dbus.service.Object):
    def __init__(self, bus, authority):
        super().__init__(bus, AGENT_PATH)
        self.bus = bus
        self.authority = authority
        self.handle = bus.get_unique_name()
        self.cookie = None
        self.pending = False
        self.awaiting_input = False
        self.proc = None
        self.reader = None
        self._reply = None
        self._error = None
        self._idle = 0
        GLib.timeout_add(POLL_MS, self._poll)

    # -- polkit -> agent --------------------------------------------------
    @dbus.service.method(IFACE, in_signature="sssa{ss}sa(sa{sv})", out_signature="",
                         async_callbacks=("reply_handler", "error_handler"))
    def BeginAuthentication(self, action_id, message, icon_name, details, cookie,
                            identities, reply_handler, error_handler):
        # The conversation cookie and the D-Bus reply are held open until the
        # helper finishes: polkitd has no timeout on this call and inspects the
        # session state (set by the helper) when we reply.
        self.cookie = cookie
        self.pending = True
        self.awaiting_input = False
        self._reply = reply_handler
        self._error = error_handler
        self._idle = 0
        self._spawn_helper(identities)
        self._poke(["prompt", message or "", action_id or "", self._identity_name(identities)])

    @dbus.service.method(IFACE, in_signature="s", out_signature="")
    def CancelAuthentication(self, cookie):
        if cookie != self.cookie:
            return
        self._cancel(reply_to_polkitd=True)

    # -- helper conversation ---------------------------------------------
    def _spawn_helper(self, identities):
        user = self._identity_name(identities) or pwd.getpwuid(os.getuid()).pw_name
        try:
            self.proc = subprocess.Popen(
                [HELPER, user],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                text=True, bufsize=1,
            )
            # The cookie travels on stdin so it is invisible to other processes.
            self.proc.stdin.write(self.cookie + "\n")
            self.proc.stdin.flush()
        except Exception as exc:  # helper missing or not setuid — nothing to fall back to
            sys.stderr.write(f"polkit agent: cannot start helper: {exc}\n")
            self._finish(False)
            return
        self.reader = threading.Thread(target=self._read_helper, daemon=True)
        self.reader.start()

    def _read_helper(self):
        """Blocking reader thread; marshals helper lines onto the GLib loop."""
        try:
            for line in self.proc.stdout:
                line = line.rstrip("\n")
                if line.startswith("PAM_PROMPT_ECHO_OFF "):
                    GLib.idle_add(self._on_prompt, line[len("PAM_PROMPT_ECHO_OFF "):])
                elif line.startswith("PAM_PROMPT_ECHO_ON "):
                    GLib.idle_add(self._on_prompt, line[len("PAM_PROMPT_ECHO_ON "):])
                elif line.startswith("SUCCESS"):
                    GLib.idle_add(self._finish, True)
                elif line.startswith("FAILURE"):
                    GLib.idle_add(self._finish, False)
        except Exception:
            pass

    def _on_prompt(self, _text):
        # The helper is blocked on stdin waiting for the user's answer; the
        # authorize face is already on screen (or re-shown by a re-poke).
        if not self.pending:
            return False
        self.awaiting_input = True
        self._idle = 0
        return False

    # -- response file polling --------------------------------------------
    def _poll(self):
        if not self.pending or not self.awaiting_input:
            return True
        if not os.path.exists(RESP_FILE):
            self._idle += POLL_MS
            if self._idle > 5 * 60 * 1000:  # nobody answered — give up
                self._cancel(reply_to_polkitd=True)
            return True
        try:
            with open(RESP_FILE, "r", encoding="utf-8") as f:
                content = f.read()
        finally:
            try:
                os.unlink(RESP_FILE)
            except OSError:
                pass
        self._idle = 0
        if content.strip() == "CANCEL":
            self._cancel(reply_to_polkitd=True)
        else:
            self.awaiting_input = False
            if self.proc is not None:
                try:
                    self.proc.stdin.write(content + "\n")
                    self.proc.stdin.flush()
                except Exception:
                    pass
        return True

    # -- completion -------------------------------------------------------
    def _finish(self, success):
        # The helper already told polkitd the result on success; replying
        # normally lets polkitd conclude (is_authenticated was set by the
        # helper). On failure no response ever arrived, so a plain reply means
        # denied.
        self._kill_helper()
        self._poke(["clear"])
        self._close_conversation(error=None if success else None)
        return False

    def _cancel(self, reply_to_polkitd):
        self._kill_helper()
        self._poke(["clear"])
        if reply_to_polkitd and self._error is not None:
            exc = dbus.exceptions.DBusException(
                "Authentication cancelled",
                name="org.freedesktop.PolicyKit1.Error.Cancelled")
            self._close_conversation(error=exc)
        else:
            self._close_conversation(error=None)

    def _close_conversation(self, error):
        reply, self._reply = self._reply, None
        err, self._error = self._error, None
        self.pending = False
        self.awaiting_input = False
        self.cookie = None
        if reply is not None:
            try:
                if error is not None:
                    err(error)
                else:
                    reply()
            except Exception:
                pass

    def _kill_helper(self):
        if self.proc is not None:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=2)
            except Exception:
                try:
                    self.proc.kill()
                except Exception:
                    pass
        self.proc = None
        self.reader = None

    # -- shell bridge -----------------------------------------------------
    def _poke(self, args):
        # The shell runs as `qs -p <configdir>`; without the path quickshell
        # cannot find the config to talk to, so the pokes would vanish. The
        # agent lives at <config>/utils/polkit/agent.py, so the config root is
        # three directories up.
        config = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        try:
            subprocess.run(["quickshell", "-p", config, "ipc", "call", "polkit"] + args,
                           timeout=5, capture_output=True, text=True)
        except Exception:
            pass

    @staticmethod
    def _identity_name(identities):
        try:
            if identities and len(identities) >= 1:
                ident = identities[0]
                if len(ident) >= 2:
                    kind = str(ident[0])
                    details = ident[1]
                    if kind == "unix-user" and details.get("uid") is not None:
                        return pwd.getpwuid(int(details["uid"])).pw_name
        except Exception:
            pass
        return ""


def main():
    os.makedirs(BASE, exist_ok=True)
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    # polkitd and the agent interface both live on the system bus; the
    # "session" registration ties this agent to our login session.
    bus = dbus.SystemBus()
    authority = bus.get_object(AUTHORITY_NAME, AUTHORITY_PATH)
    agent = Agent(bus, authority)

    session_id = os.environ.get("XDG_SESSION_ID", "")
    if not session_id:
        try:
            out = subprocess.run(["loginctl", "show-session", "-p", "Id"],
                                 capture_output=True, text=True, timeout=3)
            session_id = out.stdout.strip().split("=")[-1].strip()
        except Exception:
            session_id = ""
    if not session_id:
        sys.stderr.write("no session id, not registering polkit agent\n")
        sys.exit(1)

    subject = dbus.Struct(
        ("unix-session", dbus.Dictionary({"session-id": session_id}, signature="sv")),
        signature="sa{sv}")
    authority.RegisterAuthenticationAgentWithOptions(
        subject, "C", AGENT_PATH,
        dbus.Dictionary({}, signature="sv"),
        dbus_interface="org.freedesktop.PolicyKit1.Authority")
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
