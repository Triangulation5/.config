#!/bin/sh
#
# Shared Rust toolchain detection and `useRustTools` preference helpers.
# Compatible with both POSIX `/bin/sh` and `bash`.
#
# Ensures `${CARGO_HOME:-$HOME/.cargo}/bin` is checked and exposed on PATH even
# when Hyprland starts from a display manager or TTY before login-shell rc files
# have sourced `~/.cargo/env`.
#

rust_ensure_path() {
    _cargo_bin="${CARGO_HOME:-${HOME:-}/.cargo}/bin"
    if [ -n "${HOME:-}${CARGO_HOME:-}" ] && [ -d "$_cargo_bin" ]; then
        case ":${PATH:-}:" in
            *":$_cargo_bin:"*) ;;
            *)
                PATH="$_cargo_bin${PATH:+:$PATH}"
                export PATH
                ;;
        esac
    fi
    unset _cargo_bin
}

has_rust_toolchain() {
    rust_ensure_path
    command -v cargo >/dev/null 2>&1 || command -v rustc >/dev/null 2>&1
}

has_cargo_toolchain() {
    rust_ensure_path
    command -v cargo >/dev/null 2>&1
}

rust_pref_enabled() {
    [ "${SILHOUETTE_NO_NATIVE:-0}" != "1" ] || return 1
    [ "${SILHOUETTE_FORCE_SHELL:-0}" != "1" ] || return 1
    [ "${SILHOUETTE_FORCE_PYTHON:-0}" != "1" ] || return 1
    _rust_flags="${XDG_STATE_HOME:-${HOME:-}/.local/state}/silhouette/flags.json"
    if [ -r "$_rust_flags" ] &&
       grep -Eq '"(useRustTools|rustWallpapers)"[[:space:]]*:[[:space:]]*false' "$_rust_flags"; then
        unset _rust_flags
        return 1
    fi
    unset _rust_flags
    return 0
}

rust_tools_usable() {
    rust_pref_enabled && has_rust_toolchain
}
