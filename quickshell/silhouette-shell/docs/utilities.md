# Utilities

<!--toc:start-->
- [Utilities](#utilities)
  - [Calculator](#calculator)
  - [Tooltips](#tooltips)
  - [Keybind system](#keybind-system)
<!--toc:end-->

## Calculator

Built into the launcher. Type an expression instead of a query and it
evaluates it inline, so quick math does not need a separate app.

## Tooltips

A washi hint bubble anchored to whatever pill control you hover. It explains
what the control does instead of making you guess from an icon.

## Keybind system

Shortcuts are managed from the keybinds surface, which parses `binds.lua`,
supports chord capture and writes the minimal set of changes back. The
shell's own key routing (arrow navigation, vim keys, backspace to back out)
is separate from the Hyprland binds and lives in the pill's nav module.
