#!/bin/sh
#
# Shell supervisor dispatcher. Uses the zero-fork Rust watchdog in
# `silhouette-tools` when Rust is installed and `useRustTools` is enabled, and
# falls back to the portable POSIX shell implementation (`watchdog-fallback.sh`)
# otherwise.
#
name="${1:-}"
[ -n "$name" ] || exit 1

scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/lib-rust.sh
. "$scripts_dir/lib/lib-rust.sh"

rust_bin="$scripts_dir/bin/silhouette-tools"

if rust_tools_usable &&
   [ -x "$rust_bin" ] &&
   "$rust_bin" watchdog --help >/dev/null 2>&1; then
    exec "$rust_bin" watchdog "$name" --scripts-dir "$scripts_dir"
fi

exec sh "$scripts_dir/watchdog-fallback.sh" "$name"
