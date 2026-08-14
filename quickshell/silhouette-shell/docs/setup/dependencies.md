# Dependencies

<!--toc:start-->
- [Dependencies](#dependencies)
  - [Required](#required)
  - [Optional](#optional)
<!--toc:end-->

The shell shells out to these tools, so the list is what it actually needs.
Missing pieces degrade the related feature, not the whole shell.

## Required

- Quickshell (the shell itself)
- Hyprland
- NetworkManager (`nmcli`) for wifi and hotspot
- BlueZ (`bluetoothctl`) for bluetooth
- cliphist for clipboard history
- wl-clipboard for clipboard copy
- cava for the audio visualizers
- gpu-screen-recorder for recording (full feature set: window/region picks,
  cursor capture, hardware encoding). Without it the shell falls back to
  plain ffmpeg (full screen, root capture) — see [recording.md](recording.md)
- slurp and jq for region and window picking
- curl for wallpaper and weather fetching
- brightnessctl for the internal panel brightness
- ddcutil for external monitor brightness

## Optional

- kdialog or zenity, the native folder picker (zenity is the fallback)
- python3-dbus, for the polkit authentication agent that puts admin prompts
  on the pill (see [authentication.md](authentication.md))
- howdy, for face unlock on the lock screen (see [face-unlock.md](face-unlock.md))
- nvibrant, if you want NVIDIA display saturation
- xrandr, for XWayland display handling

Standard tools the shell also assumes: bash, coreutils, systemd, xdg-utils.
