# Display & Hardware

<!--toc:start-->
- [Display & Hardware](#display-hardware)
  - [Display switcher](#display-switcher)
  - [Volume / brightness OSD](#volume-brightness-osd)
  - [Battery OSD](#battery-osd)
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

## Battery OSD

The pill morphs open for power events on laptops: plugging in, unplugging,
charging starting below a charge threshold, and every whole percent gained
while charging. The flash reads like the other level faces — bolt glyph,
charge meter, percentage — flame-lit while the cable is in and washed slate
on battery. While the pack actually takes charge a warm shimmer sweeps the
meter, and the fill rides the live charge level, so a flash held open across
a gain tick shows the bar move. In game mode the same read rides the inline
chip on the game bar instead, like volume and brightness already do.

## Bluetooth

Managed through bluetoothctl. The link surface discovers devices, pairs and
connects to them, and keeps the state synced with NetworkManager so the
bluetooth and wifi views agree.

The Bluetooth drill-in splits into a CONNECTED block over the nearby list.
Connected controllers, mice and headsets show their charge as a full-width
battery thread with the percent; USB-dongle peripherals join them tagged USB
and read-only. Percentages come from UPower via the Peripherals singleton,
since BlueZ only publishes Battery1 with its Experimental flag on: a UPower
device whose path carries a MAC is matched to its Bluetooth row, and the
BlueZ battery is kept as a fallback. The Bluetooth row on the link surface
lights up while something is connected and shows the lowest peripheral
percent once any device drops to 20%, and each device that low raises one
notification.

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
