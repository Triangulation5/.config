# Settings

<!--toc:start-->
- [Settings](#settings)
  - [Quick settings index](#quick-settings-index)
  - [Appearance](#appearance)
  - [Keybinds](#keybinds)
  - [Display](#display)
  - [Updates](#updates)
  - [Shell tuning](#shell-tuning)
  - [Backups](#backups)
  - [Persistent configuration](#persistent-configuration)
<!--toc:end-->

## Quick settings index

The pill's settings menu (the cog) is the category hub, rebranded Quick
Settings (速). It keeps the original group-and-morph browsing: rows for
Appearance, Look, Display, Input, Animation, Keybinds, Workspaces, Idle/Lock
and Updates, arrow keys moving the glowing seam and Return opening the
sub-surface, which morphs back on the back chevron or an empty click. Also
reachable over the pill's IPC: `qs ipc call pill settings`.

## Appearance

Clock format and seconds, the Japanese-glyph toggle that gates every surface
header, palette mode (static, dynamic, manual hue), UI scale and reduce
motion. Manual mode reveals a rainbow hue strip and a dark/light choice.

## Keybinds

A searchable list of shortcuts parsed from `binds.lua`. Each row is a combo
chip plus the action name, and hovering reveals the underlying command.
Tapping a row opens a form prefilled for editing with chord capture, a name
and a command. A dashed bar opens the same form empty to add a new binding.
Saving folds the minimal set of changes back into binds.lua.

## Display

Monitor layout, resolution, refresh rate and scaling per output, plus
workspace rule assignment. See [Display & Hardware](display-hardware.md).

## Updates

The check/apply engine lives in a singleton so the state survives surface
churn. The surface is pure presentation on top of it. Applying pulls the
latest config, relaunches the shell and raises a toast naming what landed.

## Shell tuning

The settings window reaches past the flags into the shell's own constants and the
compositor's files the pill's surfaces never touched. `Corners` (the screen-corner
radii, bezel shadow and collapse time), `Timers` (the pill's eviction sweep and
hover grace, the overlay hold, notification popup life), `Motion`'s shell speed
slider — one multiplier that scales every duration `services/Motion.qml` hands
out — and the lock surface's field, avatar, blur spread and bead timeline. None
of it needed a new config file: the surface components simply stopped holding the
numbers themselves.

## Backups

The settings window can also *record* the shell's own config rather than edit it:
the tree in `~/.config/quickshell/silhouette-shell` and the state the shell keeps
beside the flags (the flags, the calendar's events, the chosen wallpaper) go into
one timestamped archive under `~/.local/state/ricelin/backups/`, and any of those
archives can be put back — the running shell reloads what it watches, so a restore
lands without a restart. The work is `utils/backup.py`; the page is
`modules/settingsapp/`'s own (see its README for the contract and the safety
rules). Nothing on the pill does this: the surfaces here edit live settings, they
do not snapshot anything.

The settings window has an icon of its own — a cog in the shell's accent with the
shell's own pill cut out of its middle,
`modules/settingsapp/assets/silhouette-settings.svg` — worn in its rail and named
by a desktop entry, so a dock or a launcher draws it like any other app.

## Persistent configuration

Settings persist to JSON through the Flags service, so everything you change
in the surfaces survives a restart without editing config files by hand.
