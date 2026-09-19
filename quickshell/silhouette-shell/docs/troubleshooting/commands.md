# Recording fails with "no video encoder was specified"

<!--toc:start-->
- [Recording fails with "no video encoder was specified"](#recording-fails-with-no-video-encoder-was-specified)
  - [Problem](#problem)
  - [Cause](#cause)
  - [Fix](#fix)
  - [Verify](#verify)
  - [Notes](#notes)
- [Recording falls back to ffmpeg](#recording-falls-back-to-ffmpeg)
  - [Why](#why)
  - [Setup](#setup)
  - [Limits](#limits)
- [Settings, calendar or wallpaper came up empty after the rename](#settings-calendar-or-wallpaper-came-up-empty-after-the-rename)
  - [Problem](#problem-1)
  - [Cause](#cause-1)
  - [Fix](#fix-1)
  - [Verify](#verify-1)
  - [Notes](#notes-1)
<!--toc:end-->

## Problem

gpu-screen-recorder reports `Recording failed` with:

> gsr error: no video encoder was specified and neither h264, hevc nor av1
> are supported on your system

The `gsr_kms_client_init` lines earlier in the output are informational. The
KMS server connects fine. The failure is the encoder line.

## Cause

Fedora ships `ffmpeg-free`, a patent-free build of ffmpeg. It excludes the
encoders gsr needs: `libx264` for CPU encoding and the `h264_vaapi` /
`hevc_vaapi` profiles for hardware encoding. gsr links against that system
ffmpeg, so it finds no usable encoder at all. The shell passes
`-fallback-cpu-encoding yes`, but the fallback targets `libx264`, which is
also missing. Only `libopenh264` is present and gsr does not use it.

## Fix

Enable the RPM Fusion free repository and swap `ffmpeg-free` for the full
build:

```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
```

The swap pulls in `libx264` and the VAAPI wrappers. gsr links libavcodec
dynamically, so it picks up the new encoders without a reinstall.

## Verify

```bash
ffmpeg -hide_banner -encoders 2>/dev/null | grep -E 'libx264|h264_vaapi|hevc_vaapi'
```

Then try a short recording (SIGINT finalizes and saves):

```bash
rm -f /tmp/gsr-fix-test.mp4
timeout -s INT 6 gpu-screen-recorder -w screen -f 30 -q high -o /tmp/gsr-fix-test.mp4
ls -la /tmp/gsr-fix-test.mp4
```

With the encoders present, gsr records with hardware h264 via the
already-installed `libva-intel-media-driver`. The shell's
`-fallback-cpu-encoding yes` still covers the case where hardware encoding is
unavailable later.

## Notes

- `libva-intel-driver` (i965) is not packaged for Fedora 44. The iHD driver,
  already installed, is the right one for this Kaby Lake iGPU.
- If you would rather not swap system ffmpeg, the gsr flatpak bundles its own
  full ffmpeg and sidesteps this entirely:
  https://flathub.org/apps/com.dec05eba.gpu_screen_recorder

# Recording falls back to ffmpeg

## Why

The recorder runs gpu-screen-recorder when it is installed. When it is
missing, or exits non-zero before it ever starts recording, the shell
retries with a ffmpeg capture over the Wayland screen-share portal and shows
a warning (a strip under the recorder action bar, a "· ffmpeg" tag in the
spec line, and one notification per session). The fallback
(`utils/recording/portal_capture.py`) opens an
`org.freedesktop.portal.ScreenCast` session, pipes the raw frames through
PipeWire/gst into ffmpeg (libx264, CPU), and captures the default
sink/source through pulse. No root is needed.

## Setup

- The portal stack must be running: `xdg-desktop-portal` and
  `xdg-desktop-portal-hyprland` (Fedora: `sudo dnf install
  xdg-desktop-portal-hyprland`). Both already run in a stock Hyprland
  session.
- On the first recording the portal shows its share picker (choose the
  monitor, then confirm). The choice is remembered via the portal's
  `persist_mode` restore token, cached under
  `$XDG_CACHE_HOME/silhouette/rec-restore-token`, so later recordings start
  without the picker.

## Limits

- **Picker on first use** — the first recording needs one picker
  confirmation; later ones reuse the remembered choice.
- **CPU encode** — libx264 with the UI quality mapped to a crf value.
- The pipeline is `gst-launch-1.0 pipewiresrc ... ! fdsink | ffmpeg -f
  rawvideo ...`; a raw pipe ends with a partial frame, so ffmpeg exits
  non-zero even on success — the script judges success by probing the
  finished file, not the exit code.


# Settings, calendar or wallpaper came up empty after the rename

The shell's state, cache and wallpaper files used to live under `ricelin`
names, and now live under `silhouette` ones. This is the recovery when a
session comes up as if it were new.

## Problem

The pill comes up with default flags, the calendar has no events, the wallpaper
strip is blank, and the launcher has forgotten which apps were used.

## Cause

The shell reads its state by path, and the rename moved every one of them:
`~/.local/state/ricelin/flags.json` is now
`~/.local/state/silhouette/flags.json`, and the caches, the AppImage registry
and the wallpaper state moved with it. A session that starts without the
migration running is reading new, empty paths — the old files are still sitting
under their old names.

## Fix

`hypr/scripts/migrate-state.sh` carries the old tree over, and `launch.sh` runs
it before the shell starts, so a restart is usually the whole fix:

```bash
~/.config/hypr/scripts/reload.sh    # or Super + R
```

To run the migration on its own, it is idempotent and only moves a path when
the old one exists and the new one does not:

```bash
sh ~/.config/hypr/scripts/migrate-state.sh
```

## Verify

```bash
ls ~/.local/state/silhouette/flags.json ~/.local/state/silhouette-wallpaper
```

Both should exist. If they do and the shell is still empty, it was started
without `launch.sh` — start it through `~/.config/hypr/scripts/launch.sh` so the
migration and the jemalloc tuning both apply.

## Notes

- It rewords absolute paths recorded before the rename, not only the files: the
  AppImage registry's icon paths, the `Icon=` lines in the desktop entries it
  wrote, and the wallpaper folder in `flags.json`. Without that, an icon or the
  wallpaper strip would point into a directory that has moved.
- It leaves `~/.local/share/applications/ricelin-<slug>.desktop` alone. The
  launcher detects both prefixes, and reinstalling one of those apps drops the
  old entry as it writes the new one.
- It moves `~/Ricelin/wallpapers` to `~/Silhouette/wallpapers`, the folder a
  dropped wallpaper lands in. Only that subdirectory moves; `~/Ricelin` itself
  stays put when it holds anything else, such as a checkout of the upstream
  project.
- Set `XDG_STATE_HOME`, `XDG_CACHE_HOME` and `XDG_DATA_HOME` to whatever the
  shell runs with, if it does not use the defaults.
