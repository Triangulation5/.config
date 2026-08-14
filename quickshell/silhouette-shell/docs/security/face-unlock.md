# Face Unlock (Howdy)

<!--toc:start-->
- [Face Unlock (Howdy)](#face-unlock-howdy)
  - [How it fits](#how-it-fits)
  - [1. Install howdy](#1-install-howdy)
  - [2. Point howdy at the IR camera](#2-point-howdy-at-the-ir-camera)
  - [3. Enroll your face](#3-enroll-your-face)
  - [4. Wire it into the lock's PAM stack](#4-wire-it-into-the-locks-pam-stack)
  - [5. Test it](#5-test-it)
  - [Troubleshooting](#troubleshooting)
  - [Caveats](#caveats)
<!--toc:end-->

Face unlock via [Howdy](https://github.com/boltgolt/howdy), the Windows
Hello-style IR camera PAM module. The lock screen never needs to know about
it: howdy plugs into the same PAM conversation the lock already runs, so a
face match unlocks directly and a miss falls through to the password field.

This machine (Fedora 44) has an IR camera at `/dev/video0` ("Integrated IR
Camera"), which is exactly what makes howdy fast and reliable. A plain RGB
webcam works too but is slow and easily fooled — the IR camera is the right
setup.

## How it fits

- The lock authenticates through `quickshell-lock` PAM service
  (`/etc/pam.d/quickshell-lock`), via `PamContext` in `modules/lock/Auth.qml`.
- The PAM stack already layers `pam_unix` (password) and `pam_fprintd`
  (fingerprint). Face unlock is one more module in the same file.
- PAM config is read per conversation — no shell or daemon restart needed.

## 1. Install howdy

Howdy ships from a COPR, not the Fedora repos:

```bash
sudo dnf copr enable principis/howdy
sudo dnf install howdy
```

On Fedora 43+ the stable COPR can lag behind (missing `python3dist(dlib)`).
If the install fails, use the beta COPR instead, which rebuilds for the
current release:

```bash
sudo dnf copr enable principis/howdy-beta
sudo dnf install howdy
```

Verify it landed:

```bash
howdy --version
ls /usr/lib64/security/pam_howdy.so   # should exist
```

## 2. Point howdy at the IR camera

Howdy's default config points at `/dev/video0`, which on this machine **is**
the IR camera (`/dev/video2` is the RGB webcam — don't use that one).
Double-check the mapping first:

```bash
for d in /sys/class/video4linux/*; do echo "$d: $(cat "$d/name")"; done
```

Edit the config (or run `sudo howdy config` to open it in an editor):

```bash
sudoedit /etc/howdy/config.ini
```

Make sure these keys read:

```ini
device_path = /dev/video0
use_ir = true
```

Then run the self-test. It opens a window showing the IR view with a face
box, and re-enrolls nothing:

```bash
sudo howdy test
```

The first run compiles the dlib models and can take 20-30 seconds; after
that it is fast. If the view is black, the IR emitter isn't lighting — see
[Troubleshooting](#troubleshooting).

## 3. Enroll your face

```bash
sudo howdy add
```

It prompts for a label (anything, e.g. `me`) then captures several frames.
You can add more poses later (`sudo howdy add`) or list what's stored
(`sudo howdy list`). Re-enroll when the model drifts (new glasses, beard,
lighting) — `sudo howdy remove <label>` then add again.

## 4. Wire it into the lock's PAM stack

Edit `/etc/pam.d/quickshell-lock` and add the howdy line **above**
`pam_unix` so a match unlocks immediately and the password stays the
fallback:

```bash
sudoedit /etc/pam.d/quickshell-lock
```

It should end up like this:

```
#%PAM-1.0
# PAM configuration file for quickshell lock

auth       required     pam_env.so
auth       sufficient   pam_howdy.so
auth       sufficient   pam_unix.so try_first_pass nullok
auth       [success=1 default=ignore] pam_fprintd.so
auth       required     pam_deny.so
```

`pam_howdy.so` is `sufficient`, so a match short-circuits to success and a
miss or covered camera falls through to the password, then fingerprint —
the lock can never brick itself because the camera is blocked.

## 5. Test it

Headless PAM test first (no GUI needed). Install `pamtester` if missing:

```bash
sudo dnf install pamtester
pamtester quickshell-lock "$USER"
```

It should authenticate without asking for a password. Then test the real
lock screen:

```bash
qs ipc call lock lock
```

The lock appears, and the existing PAM conversation runs howdy before
prompting for a password. If the match succeeds the lock should just
unlock; if not, type the password as usual.

## Troubleshooting

- **Black / very dark test image** — the IR emitter isn't on. Confirm
  `device_path` is the IR device (`/dev/video0`, not `video2`), and that no
  other app holds the camera. If it still stays dark, the kernel driver may
  need a quirk; try the RGB camera (`device_path = /dev/video2`) as a
  fallback — slower, but it proves the pipeline works.
- **"No face detected"** — face too close/far, or too much backlight.
  Reposition and re-run `sudo howdy test`; then re-enroll from the same
  spot you normally sit.
- **First attempt is slow** — dlib model compilation on first run. Later
  attempts should be well under a second with IR.
- **Stopped recognizing after a while** — glasses, haircut, or lighting
  drift. Re-enroll (`sudo howdy remove <label>` then `sudo howdy add`).
- **Install failed on Fedora 43+** — use the `principis/howdy-beta` COPR
  (step 1). This is a known lag in the stable COPR.

## Caveats

Howdy is a convenience unlock, not a security boundary: there is no true
liveness detection, so a high-quality photo can potentially fool the RGB
path (much harder with IR). The password and fingerprint remain in the
stack as the real gate. If you ever want it off, remove the
`pam_howdy.so` line from `/etc/pam.d/quickshell-lock` and
`sudo dnf remove howdy`.
