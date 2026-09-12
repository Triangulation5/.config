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

Switching workspaces flashes a dot strip in the pill, one dot per workspace
with the active one lit. The dots are the union of the workspace to monitor
map from Hyprland's own workspace rules and the workspaces that currently
exist on that monitor, so every workspace appears: ruled ones before you have
visited them, and extras such as `r+1` past the last rule that would otherwise
vanish from the strip. A rule with no monitor (`monitor = ""`) is filed under
the focused monitor, so a single-monitor setup still shows its assigned
workspaces.

The strip is contiguous: every workspace number between this monitor's first
and last gets a slot, so jumping to a workspace that is not configured (9 on a
1-5 setup) shows nine dots with the ninth lit rather than a broken run. The row
is a fixed pool of slots, and a slot whose workspace is off the end collapses
to zero width and fades, taking its own gap with it — so a dot appearing or
disappearing eases into place instead of popping, and the strip is not rebuilt
mid-flash when the workspace list is re-read. `range` is also only reassigned
when its numbers actually change, so the refresh that follows a switch leaves
an unchanged strip untouched.

The strip's own size is computed from the range rather than read back from its
row. An OSD face is invisible until its flash begins and a positioner only lays
its children out on polish, so a row-derived width stayed 0 until the flash was
already running and the pill snapped to a new width mid-morph — the other half
of the flicker. With the width known up front, the pill morphs to the right size
once, and the dots ease into it.

That list is read from `hyprctl` by the `Workspacerules` singleton, not from
Quickshell's `Hyprland.workspaces` model. Hyprland 0.56 stopped sending an `id`
in `hyprctl workspaces -j`, while Quickshell 0.3.1 keys the model on that
field: every workspace parses as id 0 and collapses onto one object, `id` stays
-1 for the ones pre-created from events, and `monitor` is often null. Ranging
over the model is what made the strip show a different, short number of dots on
each workspace with the active dot never landing. `MinimizedTray` uses the same
`hyprctl`-derived data when restoring a window, for the same reason.

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
