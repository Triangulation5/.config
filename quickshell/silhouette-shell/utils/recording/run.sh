#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
rust_enabled=true
if [ "${SILHOUETTE_NO_NATIVE:-0}" = "1" ] ||
   [ "${SILHOUETTE_FORCE_SHELL:-0}" = "1" ] ||
   [ "${SILHOUETTE_FORCE_PYTHON:-0}" = "1" ] ||
   { [ -r "$FLAGS" ] && grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; }; then
    rust_enabled=false
fi

if [ "$rust_enabled" = true ]; then
    CARGO_BIN="${CARGO_HOME:-${HOME:-}/.cargo}/bin"
    if [ -n "${HOME:-}${CARGO_HOME:-}" ] && [ -d "$CARGO_BIN" ]; then
        case ":${PATH:-}:" in
            *":$CARGO_BIN:"*) ;;
            *) PATH="$CARGO_BIN${PATH:+:$PATH}"; export PATH ;;
        esac
    fi
    if ! command -v cargo >/dev/null 2>&1 && ! command -v rustc >/dev/null 2>&1; then
        rust_enabled=false
    fi
fi

if [ "$rust_enabled" = true ]; then
    if [ -x "$DIR/bin/framepump-$ARCH" ]; then
        exec "$DIR/bin/framepump-$ARCH" --portal "$@"
    elif [ -x "$DIR/framepump" ]; then
        rc=0
        "$DIR/framepump" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 1 ]; then
            exec "$DIR/framepump" --portal "$@"
        fi
    fi
fi

exec python3 "$DIR/portal_capture.py" "$@"
