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
to the pill, and clicking a toast raises the source app's window. Dragging a
toast up, left or right drags the pill into the mask wall: it dissolves at
the edge it leaves through and springs back on a short pull, or flings out
past half its width (0.6 of its height going up) or on a quick flick. The
control center shows the history with dismiss and activate actions. Notices the
shell raises about its own work go out through `notify-send` as
`SilhouetteShell` and come back through this same server, so they arrive as the
same washi toast and stay in the inbox like any other app's.

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

The card's backdrop mode is chosen in Appearance. The "bleed" option reads
the colour matugen pulled from the current wallpaper and lays it under the
blurred album art, so the card agrees with whatever is on screen and never
carries the static theme's own hues into someone's colours.

While a track with art is loaded, the rest pill wears a soft ambient aura:
the cover decoded tiny, saturated and blurred, stretched just past the pill
so its dominant colour bleeds into the desktop around it, and the same cover
colour casts the pill's shadow. Both follow the card's backdrop mode — at its
intended strength on "bleed", a whisper on "wash", off on "none" — and dim
while paused. ImageMagick averages the cover for the shadow tint, so it costs
nothing when the aura is off.

The settings window layers three controls on top of that, in an Ambient aura
card of its own next to the backdrop it answers to: an Ambient aura switch, an
Aura strength that scales the mode's own base, and an Aura shadow switch for
the tint. The backdrop mode still wins — with the backdrop on None the aura
stays off however those three read. None of the three is in the pill's Quick
Settings; they are the shape of a backdrop, not a separate effect.

## Tray

A custom tray. Items render as glyphs on a washi card, wheel scrolls the
list, and each menu opens in its own overlay window instead of being trapped
inside the pill. A separate minimized-apps row shows windows you stashed away.

## Mixer

Four vertical faders wired to real hardware: volume and mic through Pipewire,
brightness through ddcutil, vibrance through nvibrant. The header carries
do-not-disturb and keep-awake chips. Faders are keyboard and wheel navigable,
and a device picker swaps the default sink or source.
