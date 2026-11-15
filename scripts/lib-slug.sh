#!/usr/bin/env bash
# Shared slugification and formatting utilities for app management scripts.
# Sourced by appimage-install.sh and app-install.sh.

# Drop architecture and pure-version tokens (1.2.3, v2) but keep name tokens that
# carry letters, so "1Password" and "v2ray" survive while "Krita-5.2.0-x86_64"
# reduces to "Krita".
strip_tokens() {
    local base="$1" out="" tok low
    base="${base%.AppImage}"
    base="${base%.appimage}"
    local IFS='._-'
    for tok in $base; do
        [ -n "$tok" ] || continue
        low="$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')"
        case "$low" in
            x86_64 | amd64 | x86 | i386 | i686 | aarch64 | arm64 | armhf | arm | linux | gnu | glibc | musl | static | portable) continue ;;
            *) out="$out $tok" ;;
        esac
    done
    printf '%s' "${out# }"
}

slugify() {
    local s
    s="$(strip_tokens "$1")"
    s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    [ -n "$s" ] || s="app"
    printf '%s' "$s"
}

prettify() {
    local s
    s="$(strip_tokens "$1")"
    [ -n "$s" ] || s="${1%.[Aa]pp[Ii]mage}"
    printf '%s' "$s"
}

# Self-updaters rename the file and may switch channel, so repoint at the newest
# same-slug file, else the newest that differs only by channel word.
channelless() {
    printf '%s' "$1" | tr '-' '\n' | grep -vxE 'nightly|beta|alpha|canary|preview|insiders|dev|stable|rc[0-9]*' | paste -sd- - || true
}