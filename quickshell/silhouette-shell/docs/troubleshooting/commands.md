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
  `$XDG_CACHE_HOME/ricelin/rec-restore-token`, so later recordings start
  without the picker.

## Limits

- **Picker on first use** — the first recording needs one picker
  confirmation; later ones reuse the remembered choice.
- **CPU encode** — libx264 with the UI quality mapped to a crf value.
- The pipeline is `gst-launch-1.0 pipewiresrc ... ! fdsink | ffmpeg -f
  rawvideo ...`; a raw pipe ends with a partial frame, so ffmpeg exits
  non-zero even on success — the script judges success by probing the
  finished file, not the exit code.
