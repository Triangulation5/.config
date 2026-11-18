#!/bin/sh

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rust_bin="$script_dir/bin/silhouette-tools"
rust_flags="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette/flags.json"
rust_enabled=true
if [ -r "$rust_flags" ] &&
   grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$rust_flags"; then
    rust_enabled=false
fi

if [ "${SILHOUETTE_FORCE_SHELL:-0}" != 1 ] &&
   [ "$rust_enabled" = true ] &&
   command -v rustc >/dev/null 2>&1 &&
   [ -x "$rust_bin" ] &&
   "$rust_bin" app-install --help >/dev/null 2>&1; then
    exec "$rust_bin" app-install "$@"
fi

exec bash "$script_dir/app-install-fallback.sh" "$@"
