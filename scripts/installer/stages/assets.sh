#!/usr/bin/env bash
# shellcheck shell=bash
# Optional user-local fonts and the Papirus icon theme.

FONT_DIR="$HOME/.local/share/fonts"
FONT_CHOICES=()

FONT_NAMES=(JetBrainsMono Iosevka FiraCode Rubik "SF Pro")

select_asset_fonts() {
    local answer item index choice first last
    local -a choices=()

    FONT_CHOICES=()
    interactive || return 0

    say ""
    note "Choose fonts to install. SF Pro must be downloaded from Apple manually."
    note "Enter numbers separated by commas (for example 1,3), 'all', or 'none'."
    printf '      1) JetBrainsMono Nerd Font\n'
    printf '      2) Iosevka Nerd Font\n'
    printf '      3) FiraCode Nerd Font\n'
    printf '      4) Rubik\n'
    printf '      5) SF Pro (manual download)\n'
    printf '    Select fonts [none]: ' > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    answer="${answer//[[:space:]]/}"
    case "${answer,,}" in
        ""|none) return 0 ;;
        all) FONT_CHOICES=("${FONT_NAMES[@]}"); return 0 ;;
    esac

    local -A selected=()
    local -a parts=()
    IFS=',' read -r -a parts <<< "$answer"
    for item in "${parts[@]}"; do
        if [[ "$item" =~ ^([1-5])-([1-5])$ ]]; then
            first="${BASH_REMATCH[1]}"
            last="${BASH_REMATCH[2]}"
            if [ "$first" -gt "$last" ]; then
                warn "Invalid font range '$item'; no extra fonts will be installed."
                return 0
            fi
            for ((index = first; index <= last; index++)); do
                selected[$index]=1
            done
        elif [[ "$item" =~ ^[1-5]$ ]]; then
            selected[$item]=1
        else
            warn "Invalid font selection '$item'; no extra fonts will be installed."
            return 0
        fi
    done
    for choice in 1 2 3 4 5; do
        if [ "${selected[$choice]:-0}" = "1" ]; then
            choices+=("${FONT_NAMES[$((choice - 1))]}")
        fi
    done
    FONT_CHOICES=("${choices[@]}")
}

install_font() {
    local name="$1" url="" tmp archive extract_dir

    case "$name" in
        JetBrainsMono|Iosevka|FiraCode)
            url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${name}.zip"
            ;;
        Rubik)
            url="https://raw.githubusercontent.com/google/fonts/main/ofl/rubik/Rubik%5Bwght%5D.ttf"
            ;;
        "SF Pro")
            note "SF Pro is licensed by Apple and is not downloaded by this installer."
            note "Download it from https://developer.apple.com/fonts/ and install it manually."
            return 2
            ;;
        *)
            err "unknown font: $name"
            return 1
            ;;
    esac

    if [ -d "$FONT_DIR/$name" ]; then
        dim "$name is already installed"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required to download $name"
        return 1
    fi
    if [[ "$name" != "Rubik" ]] && ! command -v python3 >/dev/null 2>&1; then
        err "python3 is required to extract $name"
        return 1
    fi

    tmp="$(mktemp -d "$FONT_DIR/.${name}.XXXXXX")" || {
        err "could not create a temporary directory for $name"
        return 1
    }
    archive="$tmp/$name.zip"
    extract_dir="$tmp/extracted"
    mkdir -p -- "$extract_dir" || { rm -rf -- "$tmp"; return 1; }

    if [ "$name" = "Rubik" ]; then
        if ! progress_run "Downloading $name" \
                curl -fLsS --retry 2 --output "$extract_dir/Rubik[wght].ttf" -- "$url"; then
            err "could not download $name"
            rm -rf -- "$tmp"
            return 1
        fi
    else
        if ! progress_run "Downloading $name" \
                curl -fLsS --retry 2 --output "$archive" -- "$url"; then
            err "could not download $name"
            rm -rf -- "$tmp"
            return 1
        fi
        if ! _extract_font_archive "$archive" "$extract_dir"; then
            err "could not extract $name"
            rm -rf -- "$tmp"
            return 1
        fi
        rm -f -- "$archive"
    fi

    if ! find "$extract_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit | grep -q .; then
        err "the $name download contained no font files"
        rm -rf -- "$tmp"
        return 1
    fi
    if ! mv -- "$extract_dir" "$FONT_DIR/$name"; then
        err "could not install $name into $FONT_DIR"
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$tmp"
    note "installed $name"
    return 0
}

_extract_font_archive() {
    local archive="$1" destination="$2"
    python3 - "$archive" "$destination" <<'PY'
import os
import pathlib
import sys
import zipfile

archive, destination = sys.argv[1:]
root = os.path.realpath(destination)
with zipfile.ZipFile(archive) as fonts:
    for member in fonts.infolist():
        path = pathlib.PurePosixPath(member.filename)
        if path.suffix.lower() not in {".ttf", ".otf"}:
            continue
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"unsafe font path in archive: {member.filename}")
        target = os.path.realpath(os.path.join(root, *path.parts))
        if os.path.commonpath((root, target)) != root:
            raise ValueError(f"unsafe font path in archive: {member.filename}")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with fonts.open(member) as source, open(target, "wb") as output:
            output.write(source.read())
PY
}

stage_assets() {
    local font rc=0 manual_sf=0 icon_theme=0
    local -a failed=() icon_paths=(
        "$HOME/.local/share/icons/Papirus-Dark"
        /usr/local/share/icons/Papirus-Dark
        /usr/share/icons/Papirus-Dark
    )

    if [ "$DRY_RUN" = "1" ]; then
        dim "Papirus-Dark comes from the papirus-icon-theme distro package"
        for font in "${FONT_CHOICES[@]}"; do
            if [ "$font" = "SF Pro" ]; then
                note "SF Pro requires a manual download from Apple."
            else
                would_do run "install $font into $FONT_DIR"
            fi
        done
        STAGE_DETAIL="Papirus-Dark package; no icons downloaded"
        if [ "${#FONT_CHOICES[@]}" -gt 0 ]; then
            STAGE_DETAIL="$STAGE_DETAIL; fonts: ${FONT_CHOICES[*]}"
        fi
        return "$ST_OK"
    fi

    mkdir -p -- "$FONT_DIR" || {
        err "could not create the user font directory"
        return "$ST_FAIL"
    }

    for font in "${icon_paths[@]}"; do
        if [ -d "$font" ]; then icon_theme=1; break; fi
    done
    if [ "$icon_theme" = "0" ]; then
        warn "Papirus-Dark is not installed; check the papirus-icon-theme package in the package stage."
    fi
    for font in "${FONT_CHOICES[@]}"; do
        install_font "$font"
        rc=$?
        case "$rc" in
            0) ;;
            2) manual_sf=1 ;;
            *) failed+=("$font") ;;
        esac
    done

    if [ "${#FONT_CHOICES[@]}" -gt 0 ] && command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_DIR" || warn "font cache refresh failed; fonts may appear after the next login"
    fi
    if [ "${#failed[@]}" -gt 0 ]; then
        err "could not install fonts: ${failed[*]}"
        STAGE_DETAIL="failed: ${failed[*]}"
        return "$ST_FAIL"
    fi

    STAGE_DETAIL="Papirus-Dark package"
    if [ "${#FONT_CHOICES[@]}" -gt 0 ]; then
        STAGE_DETAIL="$STAGE_DETAIL; fonts: ${FONT_CHOICES[*]}"
    fi
    [ "$manual_sf" = "0" ] || STAGE_DETAIL="$STAGE_DETAIL; SF Pro manual"
    if [ "$icon_theme" = "0" ]; then
        STAGE_DETAIL="$STAGE_DETAIL; Papirus-Dark missing"
        return "$ST_WARN"
    fi
    return "$ST_OK"
}
