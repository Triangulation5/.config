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
an entry runs it through the launch guard: an app that dies within the first
seconds raises a critical toast with its exit code and stderr, and Copy puts
the whole thing on the clipboard.

The same picker backs the AppImage installer, the stash and space-app add
flows, so every search in the shell behaves the same way.

## AppImage installer

Drag an AppImage onto the pill to install it. The shell moves it into place,
registers it with the launcher and marks it with a `ricelin-` id prefix so
installed AppImages can be told apart from system entries. The same prefix
lets the launcher offer uninstall and rename actions on those entries.

Hovering the resting pill with a file grows a drop-zone face out of it:
corner brackets, a glyph that walks from the download arrow through a spinner
to a check, and the installer's own output streamed live underneath while it
runs, with a running clock once a slow backend passes three seconds. The face
is only the progress. The result is announced as a `SilhouetteShell`
notification — the same toast the pill raises for any other app, and the inbox
keeps it afterwards — which names what landed (or what failed, with the
installer's error as the body) a beat after the face folds back to rest. An app
install also opens the launcher over the toast so the new entry is right there.
Fonts land in the font directory and are registered in the running shell;
images become the wallpaper. A drop the installer cannot route says so on the
face and in the toast.

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
