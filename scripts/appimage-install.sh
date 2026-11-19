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
   "$rust_bin" appimage-install --help >/dev/null 2>&1; then
    rust_output=$("$rust_bin" appimage-install "$@")
    rust_status=$?
    if [ "$rust_status" -eq 0 ]; then
        case "${1:-}" in
            install)
                rust_valid=$(printf '%s\n' "$rust_output" |
                    awk -F '\t' 'NR == 1 && NF == 3 && $1 != "" && $2 != "" && $3 != "" { valid=1 } END { print (NR == 1 && valid) ? "yes" : "no" }')
                ;;
            heal)
                [ -n "$rust_output" ] && [ -f "$rust_output" ] && rust_valid=yes || rust_valid=no
                ;;
            *)
                [ -z "$rust_output" ] && rust_valid=yes || rust_valid=no
                ;;
        esac
        if [ "$rust_valid" = yes ]; then
            [ -z "$rust_output" ] || printf '%s\n' "$rust_output"
            exit 0
        fi
        printf '%s\n' "appimage-install: Rust returned invalid output; using Bash fallback" >&2
    elif [ "$rust_status" -ne 126 ] && [ "$rust_status" -ne 127 ]; then
        exit "$rust_status"
    else
        printf '%s\n' "appimage-install: Rust could not start; using Bash fallback" >&2
    fi
fi

exec bash "$script_dir/appimage-install-fallback.sh" "$@"
