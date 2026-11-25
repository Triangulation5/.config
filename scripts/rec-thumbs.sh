#!/bin/sh

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/lib-rust.sh
. "$script_dir/lib/lib-rust.sh"
rust_bin="$script_dir/bin/silhouette-tools"

if rust_tools_usable &&
   [ -x "$rust_bin" ] &&
   "$rust_bin" rec-thumbs --help >/dev/null 2>&1; then
    if "$rust_bin" rec-thumbs "${1:-}"; then
        exit 0
    fi
fi

exec "$script_dir/rec-thumbs-fallback.sh" "$@"
