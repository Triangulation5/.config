#!/bin/sh

MAGICK_CONFIGURE_PATH="$(dirname "$0")/magick-policy"
export MAGICK_CONFIGURE_PATH

# Same folder chain as wallpaper.sh, read from what it resolved: the state
# file it writes, then the flag itself, then ~/Pictures. wallpaper.sh resolve
# runs ahead of this in the shell's refresh pipeline, so the state file is
# normally the answer and the rest are only first-boot fallbacks.
wpdir=""
resolved="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper-dir"
[ -r "$resolved" ] && wpdir=$(cat "$resolved" 2>/dev/null || true)
if [ -z "$wpdir" ] && command -v jq >/dev/null 2>&1; then
    wpdir=$(jq -r '.wallpaperDir // ""' "${XDG_STATE_HOME:-$HOME/.local/state}/ricelin/flags.json" 2>/dev/null || true)
fi
[ -n "$wpdir" ] || wpdir="$HOME/Pictures"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/ricelin-wp-thumbs"
mkdir -p "$cache"

for f in "$cache"/*.png; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .png)"
    [ -n "$(find "$wpdir" -type f -name "$base" -print -quit)" ] || rm -f "$f"
done

find "$wpdir" -type f \( -iname '*.jpg' -o -iname '*.png' \) | while IFS= read -r src; do
    thumb="$cache/$(basename "$src").png"
    if [ ! -s "$thumb" ] || [ "$src" -nt "$thumb" ]; then
        magick "${src}[0]" -strip -resize 512x "png:$thumb.tmp" 2>/dev/null
        if [ -s "$thumb.tmp" ]; then
            mv "$thumb.tmp" "$thumb"
        else
            rm -f "$thumb.tmp"
        fi
    fi
done
