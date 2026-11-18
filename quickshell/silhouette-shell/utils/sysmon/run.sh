#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

FLAGS="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
rust_enabled=true
if [ -r "$FLAGS" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$FLAGS"; then
    rust_enabled=false
fi

# Tier 1: Compiled native Rust binary (arch-specific or root)
if [ "$rust_enabled" = true ]; then
    if [ -x "$DIR/bin/sysmon_sampler-$ARCH" ]; then
        exec "$DIR/bin/sysmon_sampler-$ARCH" "$@"
    elif [ -x "$DIR/sysmon_sampler" ]; then
        exec "$DIR/sysmon_sampler" "$@"
    fi
fi

# Tier 2: Python 3 persistent sampler fallback
if command -v python3 >/dev/null 2>&1 && [ -f "$DIR/sampler.py" ]; then
    exec python3 "$DIR/sampler.py" "$@"
fi

# Tier 3: Universal POSIX shell fallback
if [ -f "$DIR/sampler.sh" ]; then
    exec sh "$DIR/sampler.sh" "$@"
fi

echo "ERROR: No suitable Sysmon sampler runner found" >&2
exit 1
