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
- gpu-screen-recorder for recording
- slurp and jq for region and window picking
- curl for wallpaper and weather fetching
- brightnessctl for the internal panel brightness
- ddcutil for external monitor brightness

## Optional

- kdialog or zenity, the native folder picker (zenity is the fallback)
- nvibrant, if you want NVIDIA display saturation
- xrandr, for XWayland display handling

Standard tools the shell also assumes: bash, coreutils, systemd, xdg-utils.
