#!/usr/bin/env python3
"""
Wayland screen capture through the ScreenCast portal, encoded by ffmpeg.

Opens an org.freedesktop.portal.ScreenCast session (the compositor's
screen-share portal — on Hyprland this shows its picker once and, with
persist_mode, remembers the choice for later recordings), receives the
PipeWire connection fd, pipes the raw video through gst
(pipewiresrc -> videoconvert -> videorate -> raw I420) into ffmpeg, which
does the libx264 encode and optional pulse audio. No root needed.

The raw video pipe has no timestamps, so the width/height from the portal
stream and the requested fps are passed to ffmpeg explicitly, and videorate
pins the frame rate to what the user asked for regardless of the monitor's
refresh rate. A raw pipe delivers a partial final frame on EOF, which makes
ffmpeg exit non-zero even though every frame was encoded, so success is
judged by probing the finished file, not the exit code.

Usage:
  portal_capture.py --output FILE [--fps N] [--crf N] [--cursor yes|no]
                    [--sink NAME] [--mic NAME]

Exit codes: 0 = recording finished and the output file is valid,
            1 = cancelled / failed / empty output.
"""

import argparse
import os
import signal
import subprocess
import sys
import time

import dbus
import dbus.mainloop.glib
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST_IFACE = "org.freedesktop.portal.ScreenCast"
PIPEWIRE_IFACE = "org.freedesktop.portal.PipeWire"
REQUEST_IFACE = "org.freedesktop.portal.Request"

# ScreenCast source types / cursor modes / persist modes (portal spec).
SOURCE_MONITOR = 1
CURSOR_EMBEDDED = 1
CURSOR_METADATA = 2
PERSIST_PERMANENT = 2  # xdg-desktop-portal-hyprland accepts 1 and 2 only

PICKER_TIMEOUT = 180  # seconds to wait for the user to pick a source


def restore_token_path():
    """Where the portal-issued restore token is cached between recordings."""
    cache = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    return os.path.join(cache, "ricelin", "rec-restore-token")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--crf", type=int, default=18)
    parser.add_argument("--cursor", choices=["yes", "no"], default="yes")
    parser.add_argument("--sink", default="")
    parser.add_argument("--mic", default="")
    parser.add_argument("--persist", type=int, default=PERSIST_PERMANENT,
                        help="portal persist_mode (0 none, 1 session, 2 permanent, 3 both)")
    return parser.parse_args()


def main():
    args = parse_args()

    # Registered before the handshake so a stop signal is honoured even while
    # the picker is still up; the handshake heartbeat polls this flag.
    stopping = [False]

    def stop_handler(signum, frame):
        stopping[0] = True

    signal.signal(signal.SIGINT, stop_handler)
    signal.signal(signal.SIGTERM, stop_handler)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    portal = bus.get_object(PORTAL_NAME, PORTAL_PATH)
    screencast = dbus.Interface(portal, SCREENCAST_IFACE)
    pipewire = dbus.Interface(portal, PIPEWIRE_IFACE)

    token_n = [0]

    def token():
        token_n[0] += 1
        return "quickshell_%d_%d" % (os.getpid(), token_n[0])

    def wait_response(method, *args, **kwargs):
        """Call a portal method returning a Request path and block until its
        Response signal arrives. Returns (response_code, results_dict)."""
        loop = GLib.MainLoop()
        out = {}

        def respond(code, results):
            out["code"] = int(code)
            out["results"] = results
            loop.quit()

        def beat():
            # Heartbeat: keeps Python signal handlers (SIGINT/SIGTERM)
            # responsive while the loop waits on the picker, and aborts the
            # wait when a stop signal arrived.
            if stopping[0]:
                loop.quit()
                return False
            return True

        request_path = method(*args, **kwargs)
        req = bus.get_object(PORTAL_NAME, request_path)
        req_iface = dbus.Interface(req, REQUEST_IFACE)
        req_iface.connect_to_signal("Response", respond)
        GLib.timeout_add(200, beat)
        GLib.timeout_add_seconds(PICKER_TIMEOUT, loop.quit)
        loop.run()
        if "code" not in out:
            return 2, {}
        return out["code"], out["results"]

    try:
        code, results = wait_response(
            screencast.CreateSession,
            {"handle_token": token(), "session_handle_token": token()},
        )
        if code != 0:
            print("Screen share session could not be created (portal error %d)" % code, file=sys.stderr)
            return 1
        session = str(results["session_handle"])

        cursor_mode = CURSOR_EMBEDDED if args.cursor == "yes" else CURSOR_METADATA
        select_opts = {
            "types": dbus.UInt32(SOURCE_MONITOR),
            "multiple": dbus.Boolean(False),
            "cursor_mode": dbus.UInt32(cursor_mode),
            "persist_mode": dbus.UInt32(args.persist),
        }
        saved_token = ""
        token_path = restore_token_path()
        try:
            with open(token_path) as f:
                saved_token = f.read().strip()
        except OSError:
            pass
        if saved_token:
            select_opts["restore_token"] = saved_token

        code, results = wait_response(screencast.SelectSources, session, select_opts)
        if code != 0:
            print("Screen share selection was cancelled", file=sys.stderr)
            return 1
        # The portal issues a restore token we can replay on later runs so the
        # picker can be skipped. Cache it once a choice has been made.
        issued = results.get("restore_token", "")
        if issued and issued != saved_token:
            try:
                os.makedirs(os.path.dirname(token_path), exist_ok=True)
                with open(token_path, "w") as f:
                    f.write(str(issued))
            except OSError:
                pass

        code, results = wait_response(
            screencast.Start,
            session,
            {"handle_token": token()},
        )
        if code != 0:
            print("Screen share start was cancelled", file=sys.stderr)
            return 1

        streams = results.get("streams", [])
        if not streams:
            print("Screen share returned no streams", file=sys.stderr)
            return 1
        props = streams[0][1]
        size = props.get("size", (0, 0))
        width, height = int(size[0]), int(size[1])
        if width <= 0 or height <= 0:
            print("Screen share stream has no usable size", file=sys.stderr)
            return 1

        fd = pipewire.OpenPipeWireRemote(session, {})
        conn_fd = fd.take()
    except dbus.exceptions.DBusException as exc:
        print("Screen share portal error: %s" % exc, file=sys.stderr)
        return 1

    # The portal stream id pins pipewiresrc to the screen share node instead
    # of letting autoconnect grab the first video source it finds (which on a
    # laptop is often a camera).
    stream_id = int(streams[0][0])
    gst_cmd = [
        "gst-launch-1.0", "-q",
        "pipewiresrc", "fd=%d" % conn_fd, "target-object=%d" % stream_id,
        "!", "videoconvert",
        "!", "videorate",
        "!", "video/x-raw,format=I420,framerate=%d/1" % args.fps,
        "!", "fdsink",
    ]

    ff_cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-probesize", "32", "-analyzeduration", "0",
        "-f", "rawvideo", "-pix_fmt", "yuv420p",
        "-s", "%dx%d" % (width, height), "-framerate", str(args.fps),
        "-i", "pipe:0",
    ]

    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    server = runtime + "/pulse/native"
    inputs = []
    if args.sink:
        inputs.append(["-f", "pulse", "-server", server, "-i", args.sink + ".monitor"])
    if args.mic:
        inputs.append(["-f", "pulse", "-server", server, "-i", args.mic])
    if len(inputs) == 1:
        ff_cmd += inputs[0] + ["-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "192k"]
    elif len(inputs) == 2:
        ff_cmd += inputs[0] + inputs[1] + [
            "-filter_complex", "[1:a][2:a]amix=inputs=2:normalize=0[a]",
            "-map", "0:v", "-map", "[a]", "-c:a", "aac", "-b:a", "192k",
        ]
    else:
        ff_cmd += ["-an"]

    ff_cmd += [
        "-c:v", "libx264", "-preset", "veryfast", "-crf", str(args.crf),
        "-y", args.output,
    ]

    # A stop signal can arrive while the picker is still up, before any
    # capture process exists. Exit cleanly in that case.
    if stopping[0]:
        try:
            screencast.CloseSession(session)
        except dbus.exceptions.DBusException:
            pass
        print("Stopped before capture started", file=sys.stderr)
        return 1

    try:
        gst = subprocess.Popen(gst_cmd, stdout=subprocess.PIPE,
                               pass_fds=(conn_fd,))
    except OSError as exc:
        print("Could not start gst: %s" % exc, file=sys.stderr)
        return 1

    # gst's errors inherit stderr so the shell's failure notification can
    # surface them; ffmpeg's go to a file read on early failure.
    ff_err_path = args.output + ".ffmpeg.err"
    ff_err = open(ff_err_path, "w")
    ffmpeg = subprocess.Popen(ff_cmd, stdin=gst.stdout,
                              stdout=subprocess.DEVNULL, stderr=ff_err)
    # The parent's copy of the pipe write end; only gst should hold it.
    gst.stdout.close()

    def finish_gst():
        if gst.poll() is None:
            gst.terminate()
        try:
            gst.wait(timeout=10)
        except subprocess.TimeoutExpired:
            gst.kill()
            gst.wait()

    try:
        while True:
            if stopping[0]:
                break
            if ffmpeg.poll() is not None:
                break
            if gst.poll() is not None:
                break
            time.sleep(0.1)

        if not stopping[0]:
            # gst or ffmpeg died on its own before we asked it to stop.
            if gst.poll() is None:
                gst.terminate()
            try:
                ffmpeg.wait(timeout=10)
            except subprocess.TimeoutExpired:
                ffmpeg.kill()
                ffmpeg.wait()
            if ffmpeg.returncode != 0:
                err = ""
                try:
                    ff_err.flush()
                    with open(ff_err_path) as f:
                        err = f.read().strip()
                except OSError:
                    pass
                if err:
                    print("ffmpeg failed: %s" % err[:500], file=sys.stderr)
                else:
                    print("ffmpeg failed early (exit %d)" % ffmpeg.returncode, file=sys.stderr)
            ff_err.close()
        else:
            # Clean stop: kill gst so the pipe closes, ffmpeg sees EOF,
            # finalises the mp4 and exits on its own.
            finish_gst()
            try:
                ffmpeg.wait(timeout=30)
            except subprocess.TimeoutExpired:
                ffmpeg.kill()
                ffmpeg.wait()
    finally:
        try:
            ff_err.close()
        except NameError:
            pass
        try:
            os.unlink(ff_err_path)
        except (OSError, NameError):
            pass
        try:
            screencast.CloseSession(session)
        except dbus.exceptions.DBusException:
            pass

    # A raw pipe delivers a partial final frame on EOF, so ffmpeg exits
    # non-zero even when every frame made it into the file. Judge success by
    # the output itself.
    if os.path.exists(args.output) and output_duration(args.output) > 0:
        return 0
    print("Recording produced no usable output", file=sys.stderr)
    return 1


def output_duration(path):
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path],
            capture_output=True, text=True, timeout=15,
        )
        return float(probe.stdout.strip())
    except (ValueError, subprocess.TimeoutExpired, OSError):
        return 0.0


if __name__ == "__main__":
    sys.exit(main())
