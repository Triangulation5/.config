# Settings

<!--toc:start-->
- [Settings](#settings)
  - [Settings menu](#settings-menu)
  - [Appearance](#appearance)
  - [Keybinds](#keybinds)
  - [Display](#display)
  - [Updates](#updates)
  - [Persistent configuration](#persistent-configuration)
<!--toc:end-->

## Settings menu

The settings index lists the categories grouped into Shell and Control, each
row carrying its kanji, name and caption. Arrow keys move the focused row and
Return opens the category's sub-surface, which morphs back to the index on
the back chevron or an empty click.

Shell holds Appearance and Display. Control holds Keybinds and Updates. The
other surfaces (input, workspaces, look, animation) are reached from their
own hubs.

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
