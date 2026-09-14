# Settings

<!--toc:start-->
- [Settings](#settings)
  - [Settings window (control center)](#settings-window-control-center)
  - [Quick settings index](#quick-settings-index)
  - [Appearance](#appearance)
  - [Keybinds](#keybinds)
  - [Display](#display)
  - [Updates](#updates)
  - [Persistent configuration](#persistent-configuration)
<!--toc:end-->

## Settings window (control center)

The searchable control center is its own window — a separate layer-shell
surface, completely decoupled from the pill: no morph, no surface host, no
shared mode ladder. Open it with `qs ipc call settings toggle` (or
`show`/`hide`; an empty monitor resolves to the focused one). The window
centers a card over a dim backdrop: one flat list of every shell flag with a
search bar over the top. Typing filters the whole index live — label, caption
and alias terms, multi-token, so "warm" finds Night light and "12" finds the
clock format — and with an empty query the rows browse grouped under section
captions (Look, Manual palette, Pill, Behaviour, Media, Night light, Idle &
lock, Recording, Weather & files).

Every editor binds straight to Flags: toggles flip, segmented rows cycle,
numeric rows scrub through −/+ steppers bounded by the registry, and text
rows open an inline field on Return. Arrows move the focus, left/right
adjust, Return edits, `/` focuses the search field and Escape closes. The
panel builds lazily on first open and is torn down on hide, so an unused
window costs nothing.

The registry itself is `utils/quicksettings/registry.js`: every setting is
described once (key, type, bounds, group, search terms) and the panel is a
generic renderer over it, so adding a flag to the window is a one-object edit.
It is pure QML/JS — no C++ — and lives in its own `modules/quicksettings/`
module: rip it out by deleting the folder and the single `SettingsRoot` line
in shell.qml.

## Quick settings index

The pill's settings menu (the cog) stays the category hub, rebranded Quick
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

## Persistent configuration

Settings persist to JSON through the Flags service, so everything you change
in the surfaces survives a restart without editing config files by hand.
