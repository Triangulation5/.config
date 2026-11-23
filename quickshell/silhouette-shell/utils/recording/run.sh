#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
rust_enabled=true
if [ -r "$FLAGS" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; then
    rust_enabled=false
fi

if [ "$rust_enabled" = true ] && [ "${SILHOUETTE_NO_NATIVE:-0}" != "1" ]; then
    if [ -x "$DIR/bin/framepump-$ARCH" ]; then
        exec "$DIR/bin/framepump-$ARCH" --portal "$@"
    elif [ -x "$DIR/framepump" ]; then
        exec "$DIR/framepump" --portal "$@"
    fi
fi

exec python3 "$DIR/portal_capture.py" "$@"
