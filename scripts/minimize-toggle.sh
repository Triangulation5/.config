#!/bin/sh

scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
	# shellcheck source=lib/lib-rust.sh
	. "$scripts_dir/lib/lib-rust.sh"
	rust_bin="$scripts_dir/bin/silhouette-tools"
	if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" minimize-toggle --help >/dev/null 2>&1; then
		exec "$rust_bin" minimize-toggle
	fi
fi

aw=$(hyprctl activewindow -j 2>/dev/null)
addr=$(printf '%s' "$aw" | jq -r '.address // ""')
ws=$(printf '%s' "$aw" | jq -r '.workspace.name // ""')

[ -n "$addr" ] || exit 0

if [ "$ws" = "special:minimized" ]; then
	real=$(hyprctl monitors -j | jq -r 'map(select(.focused)) | .[0].activeWorkspace.id // 1')
	qs -c silhouette-shell ipc call pill restoreWindow "$addr|$real"
else
	qs -c silhouette-shell ipc call pill minimizeWindow "$addr"
fi
