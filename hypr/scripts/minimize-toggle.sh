#!/bin/sh

aw=$(hyprctl activewindow -j 2>/dev/null)
addr=$(printf '%s' "$aw" | jq -r '.address // ""')
ws=$(printf '%s' "$aw" | jq -r '.workspace.name // ""')

[ -n "$addr" ] || exit 0

if [ "$ws" = "special:minimized" ]; then
	real=$(hyprctl monitors -j | jq -r 'map(select(.focused)) | .[0].activeWorkspace.id // 1')
	# qs -c silhouette-shell ipc call pill restoreWindow "$addr|$real"
    # Old monolithic pill
    qs -p ~/.config/quickshell/monolithic-shell/pill ipc call pill restoreWindow "$addr|$real"
else
	# qs -c silhouette-shell ipc call pill minimizeWindow "$addr"
    # Old monolithic pill
	qs -p ~/.config/quickshell/monolithic-shell/pill ipc call pill minimizeWindow "$addr"
fi
