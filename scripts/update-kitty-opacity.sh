#!/usr/bin/env bash
set -euo pipefail

scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
    # shellcheck source=lib/lib-rust.sh
    source "$scripts_dir/lib/lib-rust.sh"
    rust_bin="$scripts_dir/bin/silhouette-tools"
    if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" kitty-opacity --help >/dev/null 2>&1; then
        exec "$rust_bin" kitty-opacity
    fi
fi

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
