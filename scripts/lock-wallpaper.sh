#!/usr/bin/env bash

set -euo pipefail

# Put the wallpaper where the minimal bar's lock can read it as its backdrop.
#
# The pill's lock opens onto a grab of the desktop: lock.sh screenshots every
# monitor before it locks and the lock surface reveals through that picture. The
# minimal bar's lock takes no grab — there is no pill to wipe a hole from, and
# the round trip per monitor is the quarter second of delay the mode exists to
# skip — so it opens onto the wallpaper instead, the one picture the machine
# already knows and needs no capture to name.
#
# This script is what puts it there, and wallpaper.sh calls it on every change:
# a pick from the wallpaper strip, a random pick from the keybind and the
# restore at login all pass through that one place, so the mirrored backdrop
# cannot fall out of step with what is on screen. The shell's own
# `Walls.current` is the lock's fallback, not its source: it is empty for the
# first moments of a shell, and it names a wallpaper that a pick trashed from
# the strip has already taken with it.
#
# The mirror is scaled down and re-encoded on the way through. The lock blurs
# its backdrop to an eighth of the screen and grades it dark before it is ever
# seen, so detail past a couple of thousand pixels buys nothing but decode time
# — and that decode is synchronous on purpose, because the frame it lands on is
# the frame that replaces the desktop. A large source read asynchronously is a
# black screen with a clock on it until it finally arrives.
#
# Silent and best-effort by design: the lock falls back to the shell's own
# picture when the mirror is missing, so nothing here is worth failing a
# wallpaper change over.
#
# Called as: lock-wallpaper.sh [picture]
# With no argument the path in the wallpaper state file is used, which is how
# wallpaper.sh calls it — re-reading that file rather than taking the path along
# means a pick that overtakes this run still ends with the right backdrop.

state="${XDG_STATE_HOME:-$HOME/.local/state}"
# What the lock reads: line one is the mirror, line two the picture it was made
# from. A pointer file rather than a name the shell could work out for itself
# because "is there a backdrop yet" is a question only a text file can answer —
# the mirror is an image, and reading it back into a string to find out would be
# absurd.
LINK="$state/silhouette-lock-wallpaper"
MIRROR="$state/silhouette-lock-wallpaper.jpg"

mkdir -p "$state"

pic="${1:-}"
if [ -z "$pic" ]; then
    [ -r "$state/silhouette-wallpaper" ] && pic=$(cat "$state/silhouette-wallpaper")
fi
[ -n "$pic" ] && [ -f "$pic" ] || exit 0

# Already current: the pointer records the picture this mirror was made from, so
# a re-run for the same wallpaper — a shell refresh, or a second apply of the
# tile already on screen — stops here. Comparing timestamps instead would be
# wrong: a pick is usually an older file than the mirror cut from it.
mirrored=""
origin=""
if [ -r "$LINK" ]; then
    { read -r mirrored; read -r origin; } < "$LINK" || true
fi
if [ -r "$MIRROR" ] && [ "$mirrored" = "$MIRROR" ] && [ "$origin" = "$pic" ]; then
    exit 0
fi

# Encoded to a temp of our own and moved over the mirror, so a lock raised
# mid-encode reads the previous backdrop instead of half a jpeg. The lock can
# land at any moment, and this runs on the same change that put the new
# wallpaper on screen. The pid in the name keeps two overlapping applies — a
# keybind draw and a pick from the strip — off each other's temp.
tmp="$MIRROR.$$.jpg"
magick "$pic" -resize '2560x2560>' -quality 92 -strip "$tmp" || {
    rm -f "$tmp"
    exit 0
}
mv -f "$tmp" "$MIRROR"

printf '%s\n%s\n' "$MIRROR" "$pic" > "$LINK.tmp" && mv -f "$LINK.tmp" "$LINK"
