# Recording

<!--toc:start-->
- [Recording](#recording)
  - [Screen recorder](#screen-recorder)
  - [Quick record](#quick-record)
  - [Recorder integration](#recorder-integration)
<!--toc:end-->

## Screen recorder

Built on gpu-screen-recorder with cross-vendor encoding (nvenc, vaapi, cpu).
The flow is pick, then countdown, then record. You choose what to record with
nothing running yet: Screen resolves to a monitor (with a sub-chooser when
you have more than one), and Window / Region feeds the Hyprland client
rectangles to slurp so a click snaps to a window and a drag draws a freeform
region. The recorder is launched with `-fallback-cpu-encoding yes`, so a
machine without working hardware encoding degrades to CPU instead of failing.

Audio uses gsr's device aliases for the default sink and source, and the
surface's faders drive those same Pipewire levels, so what you set is what
gets captured. A save row shows the output directory with change and open
actions, and the clip list shows recent recordings with ffmpeg-generated
thumbnails.

### ffmpeg fallback

If gpu-screen-recorder is not installed — or dies before it ever starts
recording — the shell records with ffmpeg over the Wayland screen-share
portal instead, and warns you about it: a strip under the action bar, a
"· ffmpeg" tag in the spec line, and one notification per session. The
fallback (`utils/recording/portal_capture.py`) opens an
`org.freedesktop.portal.ScreenCast` session, pipes the raw frames through
PipeWire/gst into ffmpeg, and captures the default sink/source through
pulse — all encoded on the CPU with libx264, no root needed. The portal
shows its share picker on the first recording and remembers the choice
afterwards; quality maps to a crf value instead of gsr's presets.

## Quick record

A keybind flow that records without opening the surface. It reuses the same
source chooser, countdown and state as the full recorder, so the behavior is
identical whether you start from the pill or the keybind.

## Recorder integration

The recorder surface lives inside the pill like any other surface. The action
bar fills over the countdown and tapping cancels, and the record dot anchors
Ame while the capture runs.
