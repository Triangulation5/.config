#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
if [ -r "$FLAGS" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; then
    exit 127
fi

if [ -x "$DIR/bin/silhouette_watchers-$ARCH" ]; then
    exec "$DIR/bin/silhouette_watchers-$ARCH" "$@"
elif [ -x "$DIR/silhouette_watchers" ]; then
    exec "$DIR/silhouette_watchers" "$@"
fi

exit 127
