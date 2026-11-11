#!/usr/bin/env bash
# shellcheck shell=bash
# User-selected fonts, icon/cursor themes, and GTK appearance.

FONT_DIR="$HOME/.local/share/fonts"
ICON_DIR="$HOME/.local/share/icons"
THEME_DIR="$HOME/.local/share/themes"
CUSTOM_CURSOR_REPO="${SILHOUETTE_CURSOR_REPO:-https://github.com/Triangulation5/macOS-cursor.git}"
VAGUE_GTK_REPO="${SILHOUETTE_VAGUE_GTK_REPO:-https://github.com/vague-theme/vague-gtk.git}"

FONT_CHOICES=()
ICON_THEME="Papirus-Dark"
CURSOR_THEME="macOS"
GTK_THEME="Vague"
ASSET_ICON_ACTIVE="$ICON_THEME"
ASSET_CURSOR_ACTIVE="$CURSOR_THEME"
ASSET_GTK_ACTIVE="$GTK_THEME"

ASSET_KIND=(font font font font font icon icon cursor cursor gtk gtk gtk)
ASSET_LABELS=(
    "JetBrainsMono Nerd Font"
    "Iosevka Nerd Font"
    "FiraCode Nerd Font"
    "Rubik"
    "SF Pro (manual Apple download)"
    "Papirus-Dark"
    "Adwaita (system)"
    "macOS (custom cursor pack)"
    "Adwaita (system)"
    "Vague (custom GTK theme)"
    "Adwaita-dark"
    "Adwaita"
)
ASSET_VALUES=(JetBrainsMono Iosevka FiraCode Rubik "SF Pro" Papirus-Dark Adwaita macOS Adwaita Vague Adwaita-dark Adwaita)
ASSET_DEFAULT_SELECTED=(0 0 0 0 0 1 0 1 0 1 0 0)
ASSET_SELECTED=()
ASSET_CURSOR=0
ASSET_FRAME_LINES=20
ASSET_RENDERED=0
ASSET_KEY=""

asset_reset_selection() {
    ASSET_SELECTED=("${ASSET_DEFAULT_SELECTED[@]}")
}

asset_toggle_current() {
    local index="$ASSET_CURSOR" kind="${ASSET_KIND[$ASSET_CURSOR]}" i
    if [ "$kind" = "font" ]; then
        if [ "${ASSET_SELECTED[$index]}" = "1" ]; then
            ASSET_SELECTED[$index]=0
        else
            ASSET_SELECTED[$index]=1
        fi
        return
    fi

    for i in "${!ASSET_KIND[@]}"; do
        if [ "${ASSET_KIND[$i]}" = "$kind" ]; then ASSET_SELECTED[$i]=0; fi
    done
    ASSET_SELECTED[$index]=1
}

asset_toggle_all_fonts() {
    local i all=1
    for i in "${!ASSET_KIND[@]}"; do
        if [ "${ASSET_KIND[$i]}" = "font" ] && [ "${ASSET_SELECTED[$i]}" != "1" ]; then
            all=0
            break
        fi
    done
    for i in "${!ASSET_KIND[@]}"; do
        if [ "${ASSET_KIND[$i]}" = "font" ]; then
            if [ "$all" = "1" ]; then ASSET_SELECTED[$i]=0; else ASSET_SELECTED[$i]=1; fi
        fi
    done
}

asset_clear_fonts() {
    local i
    for i in "${!ASSET_KIND[@]}"; do
        if [ "${ASSET_KIND[$i]}" = "font" ]; then ASSET_SELECTED[$i]=0; fi
    done
}

asset_move_cursor() {
    local delta="$1"
    ASSET_CURSOR=$((ASSET_CURSOR + delta))
    [ "$ASSET_CURSOR" -lt 0 ] && ASSET_CURSOR=0
    [ "$ASSET_CURSOR" -ge "${#ASSET_KIND[@]}" ] && ASSET_CURSOR=$((${#ASSET_KIND[@]} - 1))
}

asset_render() {
    local i group="" marker box label
    if [ "$ASSET_RENDERED" = "1" ]; then
        printf '\033[%dA\033[J' "$ASSET_FRAME_LINES" > /dev/tty
    fi
    ASSET_RENDERED=1
    printf '%sSelect appearance assets%s\n' "$BOLD" "$RESET" > /dev/tty
    printf '%s↑/↓ move · space select · a toggle all fonts · n clear fonts · enter confirm · q defaults%s\n' \
        "$DIM" "$RESET" > /dev/tty
    for i in "${!ASSET_KIND[@]}"; do
        if [ "${ASSET_KIND[$i]}" != "$group" ]; then
            group="${ASSET_KIND[$i]}"
            case "$group" in
                font)  label="Fonts (optional; SF Pro is manual)" ;;
                icon)  label="Icon theme" ;;
                cursor) label="Cursor theme" ;;
                gtk)   label="GTK theme" ;;
            esac
            printf '%s%s%s\n' "$BOLD" "$label" "$RESET" > /dev/tty
        fi
        marker=" "
        [ "$i" = "$ASSET_CURSOR" ] && marker=">"
        if [ "$group" = "font" ]; then
            box="[ ]"
            [ "${ASSET_SELECTED[$i]}" = "1" ] && box="[x]"
        else
            box="( )"
            [ "${ASSET_SELECTED[$i]}" = "1" ] && box="(*)"
        fi
        printf ' %s %s %s\n' "$marker" "$box" "${ASSET_LABELS[$i]}" > /dev/tty
    done
    printf '\n%sSelected fonts: ' "$DIM" > /dev/tty
    local selected=0
    for i in "${!ASSET_KIND[@]}"; do
        if [ "${ASSET_KIND[$i]}" = "font" ] && [ "${ASSET_SELECTED[$i]}" = "1" ]; then
            [ "$selected" -eq 0 ] || printf ', ' > /dev/tty
            printf '%s' "${ASSET_LABELS[$i]}" > /dev/tty
            selected=1
        fi
    done
    [ "$selected" = "1" ] || printf 'none' > /dev/tty
    printf '%s\n' "$RESET" > /dev/tty
}

asset_read_key() {
    local ch rest=""
    ASSET_KEY=""
    IFS= read -rsn1 -u 3 ch || { ASSET_KEY="quit"; return 0; }
    case "$ch" in
        "") ASSET_KEY="enter" ;;
        " ") ASSET_KEY="toggle" ;;
        $'\033')
            if IFS= read -rsn1 -t 0.02 -u 3 rest 2>/dev/null; then
                if [ "$rest" = "[" ] || [ "$rest" = "O" ]; then
                    local rest2=""
                    if IFS= read -rsn1 -t 0.02 -u 3 rest2 2>/dev/null; then
                        case "$rest$rest2" in
                            '[A'|'OA') ASSET_KEY="up" ;;
                            '[B'|'OB') ASSET_KEY="down" ;;
                        esac
                    fi
                fi
            fi
            ;;
        j|J) ASSET_KEY="down" ;;
        k|K) ASSET_KEY="up" ;;
        a|A) ASSET_KEY="all" ;;
        n|N) ASSET_KEY="none" ;;
        q|Q) ASSET_KEY="quit" ;;
    esac
}

asset_apply_selection() {
    local i
    FONT_CHOICES=()
    for i in "${!ASSET_KIND[@]}"; do
        [ "${ASSET_SELECTED[$i]}" = "1" ] || continue
        case "${ASSET_KIND[$i]}" in
            font) FONT_CHOICES+=("${ASSET_VALUES[$i]}") ;;
            icon) ICON_THEME="${ASSET_VALUES[$i]}" ;;
            cursor) CURSOR_THEME="${ASSET_VALUES[$i]}" ;;
            gtk) GTK_THEME="${ASSET_VALUES[$i]}" ;;
        esac
    done
}

select_assets() {
    asset_reset_selection
    interactive || { asset_apply_selection; return 0; }
    if [ "${TERM:-dumb}" = "dumb" ]; then
        note "TERM=dumb; keeping the default fonts, Papirus-Dark, macOS cursor, and Vague GTK theme."
        asset_apply_selection
        return 0
    fi
    if ! { exec 3</dev/tty; } 2>/dev/null; then
        asset_apply_selection
        return 0
    fi

    ASSET_CURSOR=0
    ASSET_RENDERED=0
    asset_render
    while :; do
        asset_read_key
        case "$ASSET_KEY" in
            up) asset_move_cursor -1 ;;
            down) asset_move_cursor 1 ;;
            toggle) asset_toggle_current ;;
            all) asset_toggle_all_fonts ;;
            none) asset_clear_fonts ;;
            enter) break ;;
            quit)
                asset_reset_selection
                note "Picker cancelled; keeping the defaults."
                break
                ;;
        esac
        asset_render
    done
    printf '\n' > /dev/tty
    exec 3<&-
    asset_apply_selection
}

asset_package_name() {
    local kind="$1"
    case "$FAMILY:$kind" in
        gentoo:papirus) printf '%s' x11-themes/papirus-icon-theme ;;
        gentoo:gtk) printf '%s' x11-themes/gnome-themes-standard ;;
        gentoo:cursor) printf '%s' x11-themes/adwaita-icon-theme ;;
        *:papirus) printf '%s' papirus-icon-theme ;;
        *:gtk) printf '%s' gnome-themes-extra ;;
        fedora:cursor) printf '%s' adwaita-cursor-theme ;;
        *:cursor) printf '%s' adwaita-icon-theme ;;
        *) return 1 ;;
    esac
}

asset_install_package() {
    local label="$1" kind="$2" package
    if ! package="$(asset_package_name "$kind")"; then
        err "no package name is known for $label on $FAMILY"
        return 1
    fi
    if [ "$NO_DEPS" = "1" ]; then
        warn "cannot install $label with --no-deps; missing package: $package"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "install package $package"
        return 0
    fi
    if [ -z "$PM" ]; then
        err "cannot install $label: no package manager was detected"
        return 1
    fi
    OUTSIDE_TXN_CHANGES=1
    if [ "$PM" = "emerge" ]; then
        install_packages_gentoo "$package"
    else
        pm_install_quiet "Installing $label" "$package"
    fi
}

asset_icon_installed() {
    [ -d "$ICON_DIR/$1" ] || [ -d "/usr/local/share/icons/$1" ] || [ -d "/usr/share/icons/$1" ]
}

asset_cursor_installed() {
    [ -d "$ICON_DIR/$1/cursors" ] || [ -d "/usr/share/icons/$1/cursors" ]
}

asset_gtk_theme_installed() {
    [ -d "$THEME_DIR/$1" ] || [ -d "/usr/local/share/themes/$1" ] || [ -d "/usr/share/themes/$1" ]
}

install_vague_gtk_theme() {
    local tmp checkout source staged
    if asset_gtk_theme_installed Vague; then return 0; fi
    if ! command -v git >/dev/null 2>&1; then
        err "git is required to download the Vague GTK theme"
        return 1
    fi
    tmp="$(mktemp -d "$THEME_DIR/.Vague.XXXXXX")" || {
        err "could not create a temporary directory for the Vague GTK theme"
        return 1
    }
    checkout="$tmp/checkout"
    if ! progress_run "Downloading Vague GTK theme" \
            env GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 -- "$VAGUE_GTK_REPO" "$checkout"; then
        err "could not download the Vague GTK theme"
        rm -rf -- "$tmp"
        return 1
    fi
    source="$checkout/Vague"
    if [ ! -f "$source/index.theme" ] ||
        [ ! -f "$source/gtk-3.0/gtk.css" ] ||
        [ ! -f "$source/gtk-4.0/gtk.css" ]; then
        err "the Vague GTK repository has an unexpected layout"
        rm -rf -- "$tmp"
        return 1
    fi
    staged="$tmp/Vague"
    if ! mkdir -- "$staged" ||
        ! cp -a -- "$source/index.theme" "$source/gtk-3.0" "$source/gtk-4.0" "$staged/"; then
        err "could not stage the Vague GTK theme files"
        rm -rf -- "$tmp"
        return 1
    fi
    if ! mv -- "$staged" "$THEME_DIR/Vague"; then
        err "could not install the Vague GTK theme"
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$tmp"
    OUTSIDE_TXN_CHANGES=1
}

install_macos_cursor() {
    local tmp checkout
    if asset_cursor_installed macOS; then return 0; fi
    if ! command -v git >/dev/null 2>&1; then
        err "git is required to download the macOS cursor theme"
        return 1
    fi
    tmp="$(mktemp -d "$ICON_DIR/.macOS.XXXXXX")" || return 1
    checkout="$tmp/checkout"
    if ! progress_run "Downloading macOS cursor theme" \
            env GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 -- "$CUSTOM_CURSOR_REPO" "$checkout"; then
        err "could not download the macOS cursor theme"
        rm -rf -- "$tmp"
        return 1
    fi
    if [ ! -f "$checkout/index.theme" ] || [ ! -d "$checkout/cursors" ]; then
        err "the macOS cursor repository has an unexpected layout"
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$checkout/.git"
    if ! mv -- "$checkout" "$ICON_DIR/macOS"; then
        err "could not install the macOS cursor theme"
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$tmp"
    OUTSIDE_TXN_CHANGES=1
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
    OUTSIDE_TXN_CHANGES=1
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
    local font package failed_any=0 manual_sf=0
    local -a failed=()

    ASSET_ICON_ACTIVE="$ICON_THEME"
    ASSET_CURSOR_ACTIVE="$CURSOR_THEME"
    ASSET_GTK_ACTIVE="$GTK_THEME"
    if [ "$DRY_RUN" = "1" ]; then
        for font in "${FONT_CHOICES[@]}"; do
            if [ "$font" = "SF Pro" ]; then
                note "SF Pro requires a manual download from Apple."
            else
                would_do run "install $font into $FONT_DIR"
            fi
        done
        if [ "$ICON_THEME" = "Papirus-Dark" ] && ! asset_icon_installed Papirus-Dark; then
            if package="$(asset_package_name papirus)"; then
                would_do run "install package $package"
            fi
        fi
        if [ "$CURSOR_THEME" = "macOS" ] && ! asset_cursor_installed macOS; then
            would_do run "clone $CUSTOM_CURSOR_REPO into $ICON_DIR/macOS"
        fi
        if [ "$GTK_THEME" = "Vague" ]; then
            if ! asset_gtk_theme_installed Vague; then
                would_do run "clone $VAGUE_GTK_REPO into $THEME_DIR/Vague"
            fi
        elif ! asset_gtk_theme_installed "$GTK_THEME"; then
            if package="$(asset_package_name gtk)"; then
                would_do run "install package $package"
            fi
        fi
        STAGE_DETAIL="fonts: ${FONT_CHOICES[*]:-none}; icons: $ICON_THEME; cursor: $CURSOR_THEME; GTK: $GTK_THEME"
        return "$ST_OK"
    fi

    mkdir -p -- "$FONT_DIR" "$ICON_DIR" "$THEME_DIR" || {
        err "could not create user asset directories"
        return "$ST_FAIL"
    }

    if [ "$ICON_THEME" = "Papirus-Dark" ] && ! asset_icon_installed Papirus-Dark; then
        if ! asset_install_package "Papirus-Dark" papirus || ! asset_icon_installed Papirus-Dark; then
            warn "Papirus-Dark is unavailable; using Adwaita icons instead"
            ASSET_ICON_ACTIVE="Adwaita"
            failed_any=1
        fi
    fi
    if [ "$ASSET_ICON_ACTIVE" = "Adwaita" ] && ! asset_icon_installed Adwaita; then
        if ! asset_install_package "Adwaita icon theme" cursor || ! asset_icon_installed Adwaita; then
            warn "Adwaita icons are unavailable; GTK will fall back to its built-in default"
            failed_any=1
        fi
    fi

    if [ "$CURSOR_THEME" = "macOS" ]; then
        if ! install_macos_cursor; then
            warn "macOS cursor theme is unavailable; using Adwaita instead"
            ASSET_CURSOR_ACTIVE="Adwaita"
            failed_any=1
        fi
    fi
    if [ "$ASSET_CURSOR_ACTIVE" = "Adwaita" ] && ! asset_cursor_installed Adwaita; then
        if ! asset_install_package "Adwaita cursor theme" cursor || ! asset_cursor_installed Adwaita; then
            warn "Adwaita cursor theme is unavailable; using the desktop default"
            failed_any=1
        fi
    fi

    if [ "$GTK_THEME" = "Vague" ] && ! install_vague_gtk_theme; then
        warn "Vague is unavailable; falling back to Adwaita-dark"
        ASSET_GTK_ACTIVE="Adwaita-dark"
        failed_any=1
    fi
    if ! asset_gtk_theme_installed "$ASSET_GTK_ACTIVE"; then
        if ! asset_install_package "$ASSET_GTK_ACTIVE" gtk || ! asset_gtk_theme_installed "$ASSET_GTK_ACTIVE"; then
            warn "$ASSET_GTK_ACTIVE is unavailable; using the GTK default theme"
            ASSET_GTK_ACTIVE="Default"
            failed_any=1
        fi
    fi

    for font in "${FONT_CHOICES[@]}"; do
        install_font "$font"
        case "$?" in
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
        STAGE_DETAIL="failed fonts: ${failed[*]}"
        return "$ST_FAIL"
    fi
    if [ "$failed_any" = "1" ]; then
        STAGE_DETAIL="using fallbacks; icons: ${ASSET_ICON_ACTIVE:-unchanged}; cursor: ${ASSET_CURSOR_ACTIVE:-unchanged}; GTK: $ASSET_GTK_ACTIVE"
        return "$ST_WARN"
    fi

    STAGE_DETAIL="icons: $ASSET_ICON_ACTIVE; cursor: $ASSET_CURSOR_ACTIVE; GTK: $ASSET_GTK_ACTIVE; fonts: ${FONT_CHOICES[*]:-none}"
    [ "$manual_sf" = "0" ] || STAGE_DETAIL="$STAGE_DETAIL; SF Pro manual"
    return "$ST_OK"
}

set_gtk_setting() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file"; then
        if ! sed -i "s|^${key}=.*|${key}=${value}|" "$file"; then
            err "could not set $key in $file"
            return 1
        fi
    else
        if ! printf '%s=%s\n' "$key" "$value" >> "$file"; then
            err "could not add $key to $file"
            return 1
        fi
    fi
}

stage_asset_settings() {
    local dark=0
    local -a files=(gtk-3.0/settings.ini gtk-4.0/settings.ini)
    if [ "$ASSET_GTK_ACTIVE" = "Adwaita-dark" ] || [ "$ASSET_GTK_ACTIVE" = "Vague" ]; then dark=1; fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do config "GTK icon $ASSET_ICON_ACTIVE, cursor $ASSET_CURSOR_ACTIVE, theme $ASSET_GTK_ACTIVE"
        would_do config "Hyprland cursor $ASSET_CURSOR_ACTIVE"
        STAGE_DETAIL="GTK $ASSET_GTK_ACTIVE; icons ${ASSET_ICON_ACTIVE:-unchanged}; cursor ${ASSET_CURSOR_ACTIVE:-unchanged}"
        return "$ST_OK"
    fi

    local file
    for file in "${files[@]}"; do
        if [ ! -f "$CONFIG_DIR/$file" ]; then
            err "missing GTK settings file: $CONFIG_DIR/$file"
            return "$ST_FAIL"
        fi
        if ! txn_protect "$file"; then
            err "could not save $file before applying the selected theme"
            return "$ST_FAIL"
        fi
    done
    if [ ! -f "$CONFIG_DIR/hypr/modules/env.lua" ]; then
        err "missing Hyprland environment settings: $CONFIG_DIR/hypr/modules/env.lua"
        return "$ST_FAIL"
    fi
    if ! txn_protect "hypr/modules/env.lua"; then
        err "could not save Hyprland environment settings before changing the cursor"
        return "$ST_FAIL"
    fi

    if [ -n "$ASSET_CURSOR_ACTIVE" ] && ! grep -q 'hl.env("XCURSOR_THEME",' "$CONFIG_DIR/hypr/modules/env.lua"; then
        err "XCURSOR_THEME is missing from $CONFIG_DIR/hypr/modules/env.lua"
        return "$ST_FAIL"
    fi
    for file in "${files[@]}"; do
        [ -z "$ASSET_ICON_ACTIVE" ] || set_gtk_setting "$CONFIG_DIR/$file" gtk-icon-theme-name "$ASSET_ICON_ACTIVE" || return "$ST_FAIL"
        [ -z "$ASSET_CURSOR_ACTIVE" ] || set_gtk_setting "$CONFIG_DIR/$file" gtk-cursor-theme-name "$ASSET_CURSOR_ACTIVE" || return "$ST_FAIL"
        set_gtk_setting "$CONFIG_DIR/$file" gtk-theme-name "$ASSET_GTK_ACTIVE" || return "$ST_FAIL"
        set_gtk_setting "$CONFIG_DIR/$file" gtk-application-prefer-dark-theme "$dark" || return "$ST_FAIL"
    done
    if [ -n "$ASSET_CURSOR_ACTIVE" ]; then
        if ! sed -i "s|hl.env(\"XCURSOR_THEME\", \".*\")|hl.env(\"XCURSOR_THEME\", \"$ASSET_CURSOR_ACTIVE\")|" \
                "$CONFIG_DIR/hypr/modules/env.lua"; then
            err "could not set the Hyprland cursor theme"
            return "$ST_FAIL"
        fi
    fi

    STAGE_DETAIL="GTK $ASSET_GTK_ACTIVE; icons ${ASSET_ICON_ACTIVE:-unchanged}; cursor ${ASSET_CURSOR_ACTIVE:-unchanged}"
    return "$ST_OK"
}
