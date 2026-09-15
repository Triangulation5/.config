# Settings

<!--toc:start-->
- [Settings](#settings)
  - [Quick settings index](#quick-settings-index)
  - [Appearance](#appearance)
  - [Keybinds](#keybinds)
  - [Display](#display)
  - [Updates](#updates)
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

## Persistent configuration

Settings persist to JSON through the Flags service, so everything you change
in the surfaces survives a restart without editing config files by hand.
