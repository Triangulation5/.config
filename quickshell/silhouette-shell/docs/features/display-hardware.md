# Display & Hardware

<!--toc:start-->
- [Display & Hardware](#display-hardware)
  - [Display switcher](#display-switcher)
  - [Volume / brightness OSD](#volume-brightness-osd)
  - [Bluetooth](#bluetooth)
  - [WiFi](#wifi)
  - [Input](#input)
<!--toc:end-->

## Display switcher

A mini map of your monitors. Drag a tile to rearrange the layout, click to
select an output, and mark one as the main display. Apply writes the layout
through the monitors.lua engine and swaps workspace loops when the monitor
order changes, so your workspaces follow the physical arrangement. Apply runs
on a short countdown, so you can back out before the layout sticks.

## Volume / brightness OSD

Volume, brightness and mute changes pop an OSD above the pill instead of
relying on the compositor's. Brightness goes through brightnessctl for the
internal panel and ddcutil for external monitors.

## Bluetooth

Managed through bluetoothctl. The link surface discovers devices, pairs and
connects to them, and keeps the state synced with NetworkManager so the
bluetooth and wifi views agree.

## WiFi

NetworkManager under the hood. The link surface lists networks, connects and
remembers credentials. The wifi glyph is hand drawn, not a stock icon. A
hotspot toggle spins up a nmcli hotspot connection and shows its network name
and password inline.

## Input

Edits the pointer, keyboard and cursor settings that live in the Hyprland Lua
modules, writing each change back to its source file so it survives a
restart. Pointer and keyboard fields rewrite input.lua and reload Hyprland.
The layout row cycles a curated list of common layouts, and cursor size and
theme apply live through `hyprctl setcursor` without a reload.
