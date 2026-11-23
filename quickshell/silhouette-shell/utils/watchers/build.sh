#!/bin/sh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
OUT_BIN="$DIR/bin/silhouette_watchers-$ARCH"
ROOT_BIN="$DIR/silhouette_watchers"
FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"

if [ -r "$FLAGS" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; then
    echo "Rust tools are disabled; skipping Watchers Rust build."
    exit 0
fi

mkdir -p "$DIR/bin"

if command -v cargo >/dev/null 2>&1; then
    echo "Building silhouette_watchers with Cargo (release)..."
    cargo build --release --manifest-path "$DIR/Cargo.toml"
    cp "$DIR/target/release/silhouette_watchers" "$OUT_BIN.tmp" && mv -f "$OUT_BIN.tmp" "$OUT_BIN"
    cp "$DIR/target/release/silhouette_watchers" "$ROOT_BIN.tmp" && mv -f "$ROOT_BIN.tmp" "$ROOT_BIN"
    echo "Built: $OUT_BIN and $ROOT_BIN"
    exit 0
elif command -v rustc >/dev/null 2>&1; then
    echo "Building silhouette_watchers with rustc directly..."
    rustc -O -C opt-level=3 "$DIR/main.rs" -o "$ROOT_BIN.tmp" && mv -f "$ROOT_BIN.tmp" "$ROOT_BIN"
    cp "$ROOT_BIN" "$OUT_BIN.tmp" && mv -f "$OUT_BIN.tmp" "$OUT_BIN"
    echo "Built: $OUT_BIN and $ROOT_BIN"
    exit 0
else
    echo "Rust compiler (cargo or rustc) not found."
    exit 1
fi
