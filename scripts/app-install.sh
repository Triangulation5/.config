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
   [ -x "$rust_bin" ] &&
   "$rust_bin" app-install --help >/dev/null 2>&1; then
    rust_output=$("$rust_bin" app-install "$@")
    rust_status=$?
    if [ "$rust_status" -eq 0 ]; then
        if [ "${1:-}" = install ]; then
            rust_line=$(printf '%s\n' "$rust_output" |
                awk -F '\t' 'NF >= 3 && NF <= 4 && $1 ~ /^(app|native|font|wallpaper)$/ && $2 != "" && $3 != "" { result=$0 } END { if (result != "") print result; else exit 1 }')
            rust_valid=$?
        else
            [ -z "$rust_output" ] && rust_valid=0 || rust_valid=1
        fi
        if [ "$rust_valid" -eq 0 ]; then
            [ -z "${rust_line:-}" ] || printf '%s\n' "$rust_line"
            exit 0
        fi
        printf '%s\n' "app-install: Rust returned invalid output; using Bash fallback" >&2
    elif [ "$rust_status" -ne 126 ] && [ "$rust_status" -ne 127 ]; then
        exit "$rust_status"
    else
        printf '%s\n' "app-install: Rust could not start; using Bash fallback" >&2
    fi
fi

exec bash "$script_dir/app-install-fallback.sh" "$@"
