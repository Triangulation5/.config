#!/bin/sh
# Builds the native framepump. Optional: portal_capture.py falls back to its
# built-in Python loop when no binary is present.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"

if [ -r "$FLAGS" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; then
    echo "Rust tools are disabled; skipping framepump Rust build."
    exit 0
fi
mkdir -p "$DIR/bin"

if command -v rustc >/dev/null 2>&1; then
    rustc --edition=2021 -O -C opt-level=3 -C panic=abort -C strip=symbols "$DIR/framepump.rs" -o "$DIR/framepump.tmp"
    mv -f "$DIR/framepump.tmp" "$DIR/framepump"
    cp "$DIR/framepump" "$DIR/bin/framepump-$ARCH.tmp"
    mv -f "$DIR/bin/framepump-$ARCH.tmp" "$DIR/bin/framepump-$ARCH"
    echo "Built: $DIR/bin/framepump-$ARCH"
else
    echo "rustc not found; portal_capture.py will use its Python fallback."
    exit 1
fi
