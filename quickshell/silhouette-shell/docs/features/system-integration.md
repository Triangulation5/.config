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

Now playing comes from the Players singleton over MPRIS. One card serves both
views, and `compact` is the whole difference between them. The media bud in the
hover face leaves it off: album art, title, artist and the large play/pause
seal (奏/休) with 前/次 skips. The full surface (SUPER+A) sets it and wears the
same card smaller: a compact transport at the card's bottom-left, above it the
brush-stroke progress bar, and on top of that bar the `0:42 / 3:45` readout. The
stroke's painted head doubles as Ame's dock. That stroke is the scrub bar: press
it and the track seeks, hold it and the pointer carries the head. A player that
cannot seek, or
a live stream with no end, keeps the stroke as a readout instead.

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
