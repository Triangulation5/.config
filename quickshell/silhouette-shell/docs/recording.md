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

## Quick record

A keybind flow that records without opening the surface. It reuses the same
source chooser, countdown and state as the full recorder, so the behavior is
identical whether you start from the pill or the keybind.

## Recorder integration

The recorder surface lives inside the pill like any other surface. The action
bar fills over the countdown and tapping cancels, and the record dot anchors
Ame while the capture runs.
