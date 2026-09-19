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

The pill's settings menu (the cog) is the category hub, a reworked Quick
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

The engine itself is `hypr/scripts/rice-update.py`, which prints one JSON object
per run: how far behind the install is, the changelog, the files whose local
edits clash with upstream, and then the apply result. Local edits survive an
update unless they are explicitly handed to upstream. The settings app has a
second Updates page for the distribution's packages, driven by
`silhouette-update.py` — see [settingsapp/README.md](../../modules/settingsapp/README.md).

## Shell tuning

Pages sit in the rail in subject order — how the shell is drawn, then the bar, then
the input and outputs, then the session and its upkeep — and the header above an
open page prints its name alone: the page's own rows say what it holds, so there is
no summary line to write or keep in sync. Pages that cannot be found by their rows,
because they build their body at runtime, are searchable by a keyword list instead.
The rail itself starts at its search field, with no title of its own above it — the
window's name is already what a dock, a taskbar or the pill's window list prints. A
row's caption is not printed under its label either: it is shown in the shell's own
tooltip bubble while that row is hovered (the same washi card the pill's chips and
tray slots wear), built on the first hover and shared by every row after it, so a
page never pays a second line per option for text only some of them need.

The rail keeps the open page's row in view and rolls to it when it is not: the
chevrons walk the pages without touching the list, so page eleven can open with the
rail still showing page one. The roll is the pill calendar's wheel — a short OutBack
with overshoot, landing the row mid-list rather than against an edge — and a row
already in view is left alone, so clicking a page never moves the rail under you.

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
one timestamped archive under `~/.local/state/silhouette/backups/`, and any of those
archives can be put back — the running shell reloads what it watches, so a restore
lands without a restart. The work is `utils/backup.py`; the page is
`modules/settingsapp/`'s own (see its README for the contract and the safety
rules). Nothing on the pill does this: the surfaces here edit live settings, they
do not snapshot anything.

The settings window has an icon of its own — a cog in the shell's accent with the
shell's own pill cut out of its middle,
`modules/settingsapp/assets/silhouette-settings.svg` — not drawn inside the window
itself, but named by a desktop entry, so a dock, a taskbar or the pill's own window
list draws it like any other app. The entry is `assets/org.quickshell.desktop`, because Quickshell's
windows report that class and a window list finds an icon by looking the class up as
a desktop-entry id; both files live in `modules/settingsapp/assets` and the install
line is in its README.

## Persistent configuration

Settings persist to JSON through the Flags service, so everything you change
in the surfaces survives a restart without editing config files by hand.
