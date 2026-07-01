#!/bin/sh

MAGICK_CONFIGURE_PATH="$(dirname "$0")/magick-policy"
export MAGICK_CONFIGURE_PATH

wpdir="$HOME/Pictures"
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
