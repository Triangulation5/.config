# SilhouetteShell

A custom Qt/QML desktop shell for Hyprland. One pill bar that morphs into
whatever surface you need: calendar, clipboard, mixer, wallpaper picker,
recorder, launcher or settings.

Built on [Ricelin](https://github.com/Gakuseei/Ricelin) by
[Gakuseei](https://github.com/Gakuseei): the pill concept, the original shell
base and the custom scripts this config started from come from there, and a lot
has been reworked locally since.

One piece takes its cue from [Ukishima](https://github.com/amanhex/ukishima),
another Quickshell shell on the same base: the system monitor's ping and network
speed test.

Not everything here is hand-written. Parts of the shell and the scripts were
written with AI assistance, and features take code or ideas from other
Quickshell projects. See [CREDITS.md](CREDITS.md) for the base and the full
list.

There is no `docs/` beside this file on purpose. Every surface, service and
script carries its reasoning in a header comment where it lives, and prose
written a directory away is prose that drifts. What follows is only what the
code cannot tell you: what has to be installed, and the two failures worth
knowing about before they happen.

## What it needs

The shell shells out for these, so the list is what it actually uses. Missing
one degrades the feature that wants it, never the session — the installer
reports what is absent at the end rather than refusing to run.

Required:

- Quickshell (the shell itself), Hyprland
- `nmcli` and `bluetoothctl` for wifi and bluetooth, `upower` for peripheral
  battery
- `cliphist` and `wl-clipboard` for clipboard history
- `notify-send` for notifications, `cava` for the visualizers
- `brightnessctl` for the internal panel, `ddcutil` for external monitors
- `slurp` and `jq` for region and window picking, `curl` for wallpapers and
  weather
- `gpu-screen-recorder` for recording, or `ffmpeg` for the fallback below

Optional: `kdialog` or `zenity` for the native folder picker, `python3-dbus` for
the polkit agent that puts admin prompts on the pill, `howdy` for face unlock,
`nvibrant` for NVIDIA saturation, `xrandr` for XWayland.

## If recording fails with "no video encoder was specified"

Fedora ships `ffmpeg-free`, which excludes the encoders gsr needs: `libx264` for
CPU encoding and the `h264_vaapi`/`hevc_vaapi` profiles for hardware encoding.
gsr links the system ffmpeg and finds nothing usable — the `-fallback-cpu-encoding
yes` the shell passes targets `libx264`, which is missing too. Swap in the full
build:

```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
```

Then `ffmpeg -hide_banner -encoders 2>/dev/null | grep -E 'libx264|h264_vaapi'`
should list them. The flatpak of gpu-screen-recorder bundles its own ffmpeg and
sidesteps this if you would rather not swap a system package.

## If gpu-screen-recorder is missing

The recorder falls back to a plain ffmpeg capture over the Wayland screen-share
portal, and says so: a strip under the action bar, a `· ffmpeg` tag in the spec
line, and one notification per session. `utils/recording/portal_capture.py`
opens an `org.freedesktop.portal.ScreenCast` session and pipes the frames
through PipeWire into ffmpeg, so no root is needed. Two things to expect: the
portal's share picker appears on the first recording and is remembered after
that (a restore token cached under `$XDG_CACHE_HOME/silhouette/`), and the
encode is CPU `libx264`. A raw pipe ends on a partial frame, so ffmpeg exits
non-zero even on success — the script judges by probing the finished file.

## If a session comes up empty

The shell reads its state by path, and those paths used to be `ricelin` ones:
`~/.local/state/silhouette/flags.json`, the caches, the AppImage registry and
the wallpaper state all moved. A session that starts without the migration
running reads new, empty paths and looks brand new — default flags, no calendar,
a blank wallpaper strip. `hypr/scripts/migrate-state.sh` carries the old tree
over and `launch.sh` runs it before the shell starts, so a restart is usually
the whole fix:

```bash
~/.config/hypr/scripts/reload.sh    # or Super + R
```

It is idempotent, moves a path only when the old one exists and the new one does
not, and also rewrites the absolute paths recorded *inside* those files — the
AppImage registry's icon paths and the wallpaper folder — which would otherwise
point into a directory that has moved.
