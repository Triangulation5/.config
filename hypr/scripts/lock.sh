#!/bin/sh
umask 077
dir="${XDG_RUNTIME_DIR:-/tmp}"
flags="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"

# The minimal bar (dwm style) has no pill and no cutout, so the lock does not
# reveal onto a grab of the desktop: it opens on the frame the trigger lands and
# takes its backdrop from the wallpaper instead. Grabbing first would put a grim
# round trip per monitor in front of the lock for a picture nothing draws — and
# the lock would be up by the time it ran, so the capture would show the lock.
if [ "$(jq -r '.barEnabled // false' "$flags" 2>/dev/null)" = "true" ]; then
    date +%s%N > "$dir/silhouette-lock-trigger"
    exit 0
fi

# Grab every monitor first so the desktop is captured while it is still live and
# on screen, then lock. The lock surface reveals onto these grabs, so they must
# exist before it mounts; showing the live desktop during the grab reads as the
# desktop simply blurring into the lock, with no flash.
for out in $(hyprctl monitors -j | jq -r '.[].name'); do
    [ -n "$out" ] || continue
    rm -f "$dir/silhouette-lock-$out.png"
    grim -o "$out" "$dir/silhouette-lock-$out.png" 2>/dev/null &
done
wait

# Poke the lock daemon through its file watch instead of spawning a whole qs client,
# which shaves the Qt client startup off the lock delay.
date +%s%N > "$dir/silhouette-lock-trigger"
