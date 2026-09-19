#!/bin/sh

MAGICK_CONFIGURE_PATH="$(dirname "$0")/magick-policy"
export MAGICK_CONFIGURE_PATH

# Same folder chain as wallpaper.sh and the strip, in the same order: the flag
# itself, then what wallpaper.sh resolved into the state file, then ~/Pictures.
# The flag has to lead, because it also wins in the other two — read the state
# file first and a folder chosen in settings has every preview outside it pruned
# as an orphan, so the strip lists images with no thumbnail to show.
wpdir=""
resolved="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette-wallpaper-dir"
if command -v jq >/dev/null 2>&1; then
    wpdir=$(jq -r '.wallpaperDir // ""' "${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json" 2>/dev/null || true)
fi
# A leading tilde comes straight from the settings field, whose placeholder is
# `~/Pictures`. The shell does not expand one that arrived in a variable, so it
# would be read as a relative path below.
case "$wpdir" in
    "~")   wpdir="$HOME" ;;
    "~/"*) wpdir="$HOME/${wpdir#"~/"}" ;;
esac
if [ -z "$wpdir" ] && [ -r "$resolved" ]; then
    wpdir=$(cat "$resolved" 2>/dev/null || true)
fi
[ -n "$wpdir" ] || wpdir="$HOME/Pictures"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/silhouette-wp-thumbs"
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
