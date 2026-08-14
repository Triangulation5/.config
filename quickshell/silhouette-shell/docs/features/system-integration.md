# System Integration

<!--toc:start-->
- [System Integration](#system-integration)
  - [Notifications](#notifications)
  - [Clipboard](#clipboard)
  - [Media](#media)
  - [Tray](#tray)
  - [Mixer](#mixer)
<!--toc:end-->

## Notifications

A notification service wraps the system NotificationServer into grouped live
and history lists with unread counts. Popups render as washi toasts anchored
to the pill, and clicking a toast raises the source app's window. The control
center shows the history with dismiss and activate actions.

## Clipboard

Searchable cliphist history. The clipboard surface lists text and image
entries, cross-fades a dismiss button on hover, and copies the selected entry
back to the clipboard on Return. Ctrl+X deletes an entry, and the wipe button
clears the whole history behind a held confirmation sweep so it cannot be
triggered accidentally.

## Media

Now playing comes from the Players singleton over MPRIS. The media bud in
the hover face shows the current track, and the full surface renders a
now-playing card: album art bleeding across the card, title, artist, the
play/pause seal (奏/休) with 前/次 skips, and a brush-stroke progress bar
whose head doubles as Ame's dock. With two or more players running the source
token opens a picker instead of guessing.

## Tray

A custom tray. Items render as glyphs on a washi card, wheel scrolls the
list, and each menu opens in its own overlay window instead of being trapped
inside the pill. A separate minimized-apps row shows windows you stashed away.

## Mixer

Four vertical faders wired to real hardware: volume and mic through Pipewire,
brightness through ddcutil, vibrance through nvibrant. The header carries
do-not-disturb and keep-awake chips. Faders are keyboard and wheel navigable,
and a device picker swaps the default sink or source.
