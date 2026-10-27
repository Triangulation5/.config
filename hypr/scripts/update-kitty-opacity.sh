#!/usr/bin/env bash
set -euo pipefail

STYLE="$HOME/.config/hypr/modules/style.lua"
OUTPUT="$HOME/.cache/silhouette/kitty-opacity"

mkdir -p "$(dirname "$OUTPUT")"

if grep -Eq 'dwmStyle[[:space:]]*=[[:space:]]*true' "$STYLE"; then
    OPACITY="1.00"
else
    OPACITY="0.94"
fi

printf 'background_opacity %s\n' "$OPACITY" > "$OUTPUT"

# Reload configuration for future windows.
kitty @ load-config >/dev/null 2>&1 || true

# Update the currently targeted Kitty window.
kitty @ set-background-opacity "$OPACITY" >/dev/null 2>&1 || true
