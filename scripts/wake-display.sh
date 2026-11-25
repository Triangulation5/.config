#!/usr/bin/env bash
set -e

scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$scripts_dir/lib/lib-rust.sh" ]; then
    # shellcheck source=lib/lib-rust.sh
    source "$scripts_dir/lib/lib-rust.sh"
    rust_bin="$scripts_dir/bin/silhouette-tools"
    if rust_tools_usable && [ -x "$rust_bin" ] && "$rust_bin" wake-display --help >/dev/null 2>&1; then
        exec "$rust_bin" wake-display
    fi
fi

hyprctl dispatch dpms on
