#!/bin/sh

STATE="$HOME/.local/state/ricelin-wallpaper"
OUT="$HOME/.config/hypr/hyprlock-wallpaper.conf"

if [ -n "$1" ]; then
    printf '%s\n' "$1" > "$STATE"
fi

BACKGROUND="$(cat "$STATE")"

printf '$background = %s\n' "$BACKGROUND" > "$OUT"
