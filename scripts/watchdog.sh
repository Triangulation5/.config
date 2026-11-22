#!/bin/sh
#
# Shell supervisor dispatcher. Uses the zero-fork Rust watchdog in
# `silhouette-tools` when `useRustTools` is enabled, and falls back to the
# portable POSIX shell implementation (`watchdog-fallback.sh`) otherwise.
#
name="${1:-}"
[ -n "$name" ] || exit 1

scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rust_bin="$scripts_dir/bin/silhouette-tools"
rust_flags="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
rust_enabled=true
if [ -r "$rust_flags" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$rust_flags"; then
    rust_enabled=false
fi

if [ "${SILHOUETTE_FORCE_SHELL:-0}" != 1 ] &&
   [ "$rust_enabled" = true ] &&
   [ -x "$rust_bin" ] &&
   "$rust_bin" watchdog --help >/dev/null 2>&1; then
    exec "$rust_bin" watchdog "$name" --scripts-dir "$scripts_dir"
fi

exec sh "$scripts_dir/watchdog-fallback.sh" "$name"
