# Authentication

<!--toc:start-->
- [Authentication](#authentication)
  - [Polkit on the pill](#polkit-on-the-pill)
  - [How it works](#how-it-works)
  - [Biometrics for prompts](#biometrics-for-prompts)
  - [Troubleshooting](#troubleshooting)
<!--toc:end-->

## Polkit on the pill

When an app needs admin rights, the password prompt appears **on the pill**
instead of a system popup: the pill morphs into a 鍵 AUTHORIZE face with the
action and message, a password capsule, and Cancel / Authenticate.

The shell runs its own polkit authentication agent
(`utils/polkit/agent.py`, autostarted with the shell). It registers with
polkitd on the **system bus** as this login session's agent, so every polkit
prompt on this session — pkexec, GParted, GNOME Disks, firewall dialogs and
the rest — routes here. There is no other agent running, so this also fixes
the "No authentication agent found" failure that pkexec hit before.

## How it works

1. An app asks polkitd to authorize something with interaction.
2. polkitd calls the agent's `BeginAuthentication` with the action, message
   and cookie — the call stays open until the conversation finishes.
3. The agent spawns the setuid helper `/usr/lib/polkit-1/polkit-agent-helper-1`
   (the same one pkttyagent uses) and hands it the cookie on stdin; the
   helper runs the `polkit-1` PAM stack as root, so the password never
   crosses D-Bus or the agent's own process boundary.
4. The agent pokes the shell (`qs -p <config> ipc call polkit prompt ...`),
   PillRoot morphs the pill into the authorize face, and PAM prompts from
   the helper are relayed to it.
5. Submitting writes the password (or CANCEL) to
   `$XDG_RUNTIME_DIR/ricelin-polkit/response` — a user-only file the agent
   reads and deletes within milliseconds, forwarding it to the helper.
6. On success the helper itself calls `AuthenticationAgentResponse2` on
   polkitd, then prints SUCCESS; the agent replies to the held
   `BeginAuthentication` and polkitd grants. A failure or cancel kills the
   helper and replies with the Cancelled error so polkitd records the
   conversation as dismissed.

The response-file bridge reuses the same file-watch IPC pattern as the lock
trigger, and the agent restarts itself if it ever crashes.

## Biometrics for prompts

The helper runs the `polkit-1` PAM stack as root, so the password field is
not the only way in:
adding a biometric module to the `polkit-1` service lets a fingerprint touch
(or howdy, once installed) unlock prompts. Create an override that layers
fingerprint on top of the vendor file:

```bash
sudo tee /etc/pam.d/polkit-1 > /dev/null <<'EOF'
#%PAM-1.0

auth       include      system-auth
auth       [success=1 default=ignore] pam_fprintd.so
account    include      system-auth
password   include      system-auth
session    include      system-auth
EOF
```

`[success=1 default=ignore]` makes a failed or missing reader fall through
to the password result — it can never lock you out of prompts. Once howdy is
built, add its line above `system-auth` so a face match unlocks before the
password is even needed:

```bash
sudo sed -i '/auth.*include.*system-auth/i auth       sufficient   pam_howdy.so' /etc/pam.d/polkit-1
```

## Troubleshooting

- **pkexec says "No authentication agent found"** — the agent isn't
  registered. Check it is running (`pgrep -f polkit/agent.py`) and that
  `XDG_SESSION_ID` is set; the shell restarts the agent 2s after it exits.
- **The pill never shows a prompt** — run `qs -p ~/.config/quickshell/silhouette-shell ipc call polkit prompt test "hello" josh`
  manually (the `-p` path is required — without it quickshell can't find the
  config); if nothing happens the ipc route is broken, and if the prompt
  opens the agent→shell leg works and the failure is on polkitd's side
  (check `journalctl -u polkit`).
- **Password accepted but nothing happens after** — confirm
  `/etc/pam.d/polkit-1` exists (the vendor `/usr/lib/pam.d/polkit-1` is
  fine); if you created an override, test it with
  `pamtester polkit-1 "$USER"`.
- **Fingerprint hint but no reader** — the hint is decorative; the stack
  falls through to the password either way.
