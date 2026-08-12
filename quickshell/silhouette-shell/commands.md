# Fix gpu-screen-recorder "no video encoder was specified" on Fedora

## Problem

`gpu-screen-recorder` reports `Recording failed` with:

> gsr error: no video encoder was specified and neither h264, hevc nor av1 are
> supported on your system

The `gsr_kms_client_init` lines earlier in the output are informational — the
KMS server connects fine. The real failure is that Fedora's `ffmpeg-free`
build excludes the patent-encumbered encoders gsr needs (`libx264`,
`h264_vaapi`, `hevc_vaapi`), so gsr finds no usable encoder at all.

## Fix: swap ffmpeg-free for the full RPM Fusion ffmpeg

Run these in a terminal (they need sudo):

```bash
# 1. Enable the RPM Fusion free repository
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm

# 2. Swap the restricted ffmpeg-free for the full ffmpeg (libx264 + vaapi h264)
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
```

## Verify

```bash
# Encoders should now include libx264 / h264_vaapi / hevc_vaapi
ffmpeg -hide_banner -encoders 2>/dev/null | grep -E 'libx264|h264_vaapi|hevc_vaapi'

# Try a 2-second test recording (SIGINT finalizes and saves)
rm -f /tmp/gsr-fix-test.mp4
timeout -s INT 6 gpu-screen-recorder -w screen -f 30 -q high -o /tmp/gsr-fix-test.mp4 -fallback-cpu-encoding yes
ls -la /tmp/gsr-fix-test.mp4
```

If `ffmpeg -encoders` shows `libx264` and `h264_vaapi`, gsr will record with
hardware encoding (Intel Quick Sync via the already-installed
`libva-intel-media-driver`). The shell also passes
`-fallback-cpu-encoding yes`, so gsr degrades to CPU encoding instead of
failing if hardware encoding is ever unavailable.

## Notes

- `libva-intel-driver` (i965) is not packaged for Fedora 44; the iHD driver
  (already installed) is the correct one for this Kaby Lake iGPU.
- `libopenh264` exists in ffmpeg-free but gsr does not use it, which is why
  the fallback needed the full ffmpeg swap.
- If you prefer, the gsr flatpak bundles its own full ffmpeg and sidesteps
  this entirely: https://flathub.org/apps/com.dec05eba.gpu_screen_recorder
