#!/usr/bin/env bash

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="$here/wallpaper-rs"
flags="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"

if [ -r "$flags" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$flags"; then
    echo "Rust tools are disabled; leaving shell fallbacks active." >&2
    exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
    echo "Rust/Cargo is not installed; shell fallbacks remain active." >&2
    exit 1
fi

cargo build --release --manifest-path "$project/Cargo.toml"
mkdir -p "$here/bin"
install -m 0755 "$project/target/release/wallpaper-rs" "$here/bin/wallpaper-rs"
