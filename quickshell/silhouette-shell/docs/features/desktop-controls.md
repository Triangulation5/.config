# Desktop Controls

<!--toc:start-->
- [Desktop Controls](#desktop-controls)
  - [App launcher](#app-launcher)
  - [AppImage installer](#appimage-installer)
  - [Power menu](#power-menu)
  - [Lockscreen](#lockscreen)
<!--toc:end-->

## App launcher

A search field over a ranked application list. Results are ranked by fuzzy
match and how often you launch them, so the entries you actually use float to
the top. The usage data is shared with the standalone launcher window. Picking
an entry executes it directly.

The same picker backs the AppImage installer, the stash and space-app add
flows, so every search in the shell behaves the same way.

## AppImage installer

Drag an AppImage onto the pill to install it. The shell moves it into place,
registers it with the launcher and marks it with a `ricelin-` id prefix so
installed AppImages can be told apart from system entries. The same prefix
lets the launcher offer uninstall and rename actions on those entries.

## Power menu

Centralized power controls: lock, idle lock, sleep, logout, restart and
shutdown. Destructive actions are gated by a heat fill that only completes
while you hold the key or button down, so a stray press cannot kill your
session. Releasing early drains the fill and cancels.

## Lockscreen

A custom lock surface using the Wayland session lock protocol. Auth goes
through PAM. The surface shows the clock and battery, and the pill does a
reveal animation into the lock. Locking is triggered through a touch file so
the compositor can fire it fast without waiting on the shell, and the trigger
is debounced so the daemon never locks itself on startup.
