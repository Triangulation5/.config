#!/usr/bin/env bash
#
# lock.sh — trigger the screen lock.
#
# Converted from sh so it can report failures through lib-notify.sh: a lock
# that silently fails to grab the desktop leaves the lock showing a stale
# backdrop, and a lock that fails to trigger at all is a security problem —
# both are worth a notification, not a quiet exit.
#
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/lib-notify.sh"

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
monitors="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)"
if [ -z "$monitors" ]; then
    notify_error "Lock" "hyprctl reported no monitors; locking without a fresh grab"
fi

pids=()
for out in $monitors; do
    [ -n "$out" ] || continue
    rm -f "$dir/silhouette-lock-$out.png"
    grim -o "$out" "$dir/silhouette-lock-$out.png" 2>/dev/null &
    pids+=("$!:$out")
done

grab_failed=0
for entry in "${pids[@]}"; do
    pid="${entry%%:*}"
    out="${entry#*:}"
    if ! wait "$pid" || [ ! -s "$dir/silhouette-lock-$out.png" ]; then
        notify_error "Lock" "grim failed to capture monitor $out"
        grab_failed=1
    fi
done

# Poke the lock daemon through its file watch instead of spawning a whole qs client,
# which shaves the Qt client startup off the lock delay.
if ! date +%s%N > "$dir/silhouette-lock-trigger"; then
    # Not triggering the lock is a real failure: the user asked to lock and the
    # desktop would stay unlocked with no visible sign.
    notify_error "Lock" "Could not write $dir/silhouette-lock-trigger — the lock did NOT engage"
    exit 1
fi

# A failed grab is not fatal (the lock still mounts, on a stale backdrop); it
# was reported above. Exit 0 so the caller still considers the lock raised.
exit 0
