# Workspaces

<!--toc:start-->
- [Workspaces](#workspaces)
  - [Workspace switcher](#workspace-switcher)
  - [Special workspaces](#special-workspaces)
  - [Stash](#stash)
  - [Space apps](#space-apps)
  - [Workspace rules](#workspace-rules)
<!--toc:end-->

## Workspace switcher

The pill shows a dot per workspace, with the active one lit. The dots read
the workspace to monitor map from Hyprland's own workspace rules, so every
assigned workspace shows up even before you have visited it. With no rules
(single monitor) they fall back to live workspaces.

## Special workspaces

The workspaces hub lists the built-in special spaces (Stash, Private,
Minimized) and every user-defined space from the Spaces store, each with its
Super+key chip. The special workspace switcher toggles them with the same
keys.

## Stash

Window classes that auto-route into the `special:stash` space, read from and
written back to `stash-apps.lua`. The surface has two views: a list of
stashed classes with a drop button, and an add view that uses the launcher's
fuzzy picker. Picking an app derives its window class from the entry's
StartupWMClass.

## Space apps

The same two-view shape as stash, but per user-defined special workspace.
Each workspace gets its own app manager through the Spaces singleton, which
owns `spaces.lua` and reloads it debounced.

## Workspace rules

Workspace to monitor assignments are configured in the display surface and
persisted through the monitors.lua engine. Rules from the compositor are read
back so the pill's indicators and the actual layout never disagree.
