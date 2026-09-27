#!/bin/sh

# Route a keybind to the running shell (hypr/modules/binds.lua).
#
# Almost everything here is a pill surface: the pill owns those IPC targets and
# each takes the monitor the call came from, so the surface name is all a bind
# has to say.
#
# `dwmBar` is the exception — the one thing in this file that is not a pill
# surface. The minimal bar's toggle lives on the shell root rather than in
# modules/bar, because a target inside the bar module is absent in exactly the
# state a bind needs it: the bar is built only while it is already on, so the one
# thing its IPC surface must outlive is the bar. It also takes no monitor
# argument, so it is answered here. Pass a second word to aim it: `dwmBar off`
# or `dwmBar on`, anything else toggles.
#
#     open-surface.sh dwmBar          -> toggle the minimal bar

if [ "$1" = "dwmBar" ]; then
	exec qs -c silhouette-shell ipc call bar "${2:-toggle}"
fi

mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
qs -c silhouette-shell ipc call pill "$1" "$mon"
