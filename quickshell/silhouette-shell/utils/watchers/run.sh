#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

if [ "${SILHOUETTE_NO_NATIVE:-0}" = "1" ] ||
   [ "${SILHOUETTE_FORCE_SHELL:-0}" = "1" ] ||
   [ "${SILHOUETTE_FORCE_PYTHON:-0}" = "1" ]; then
    exit 127
fi

FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
if [ -r "$FLAGS" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; then
    exit 127
fi

CARGO_BIN="${CARGO_HOME:-${HOME:-}/.cargo}/bin"
if [ -n "${HOME:-}${CARGO_HOME:-}" ] && [ -d "$CARGO_BIN" ]; then
    case ":${PATH:-}:" in
        *":$CARGO_BIN:"*) ;;
        *) PATH="$CARGO_BIN${PATH:+:$PATH}"; export PATH ;;
    esac
fi
if ! command -v cargo >/dev/null 2>&1 && ! command -v rustc >/dev/null 2>&1; then
    exit 127
fi

if [ -x "$DIR/bin/silhouette_watchers-$ARCH" ]; then
    exec "$DIR/bin/silhouette_watchers-$ARCH" "$@"
elif [ -x "$DIR/silhouette_watchers" ]; then
    rc=0
    "$DIR/silhouette_watchers" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 2 ]; then
        exec "$DIR/silhouette_watchers" "$@"
    fi
fi

exit 127
