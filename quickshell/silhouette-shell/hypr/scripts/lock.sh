#!/bin/sh

umask 077

dir="${XDG_RUNTIME_DIR:-/tmp}"
config="$HOME/.local/state/ricelin-wallpaper"

# Read wallpaper configuration.
#
# The file contains only the wallpaper path, for example:
#
# /home/josh/Pictures/gruvbox-streetlight.jpg
#
# Extract the path directly so it can be used by other lock components.
if [ -f "$config" ]; then
    background=$(cat "$config")
fi

# Capture each monitor before activating the lock.
#
# The lock surface can reveal onto these images instead of showing a blank
# transition. Taking the screenshots while the desktop is still visible makes
# the lock appear as a smooth blur/fade from the current session.
#
# Each monitor gets its own image:
#
#   $XDG_RUNTIME_DIR/ricelin-lock-<monitor>.png
#
# These can be used by the lock screen as their background surfaces.
for out in $(hyprctl monitors -j | jq -r '.[].name'); do
    [ -n "$out" ] || continue

    rm -f "$dir/ricelin-lock-$out.png"

    grim \
        -o "$out" \
        "$dir/ricelin-lock-$out.png" \
        2>/dev/null &
done

wait

# Trigger the lock daemon through its file watcher.
#
# Writing the timestamp is faster than launching a new Quickshell client,
# avoiding extra Qt startup time during the lock sequence.
date +%s%N > "$dir/ricelin-lock-trigger"
