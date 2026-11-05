# shellcheck shell=bash
# stages/report.sh: read-only checks and the closing message. Nothing here
# changes the machine.

# What the shell calls out to. Reported, never installed here: the packages are
# the ones in packages.sh, and anything on this list that is still missing has a
# reason.
stage_report_tools() {
    local -a missing=()
    local b

    for b in Hyprland hyprctl qs kitty cava playerctl cliphist wl-copy \
             notify-send jq curl brightnessctl nmcli bluetoothctl upower \
             wpctl python3 slurp; do
        command -v "$b" >/dev/null 2>&1 || missing+=("$b")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        STAGE_DETAIL="every tool the shell calls out to is present"
        return "$ST_OK"
    fi

    warn "missing: ${missing[*]}"
    # Quickshell gets its own line because it is the one dependency no distro
    # ships in its main repos, so it is the one people actually get stuck on.
    if has_item qs "${missing[@]}"; then
        printf '\n'
        case "$FAMILY" in
            fedora) note "quickshell: $SUDO dnf copr enable errornointernet/quickshell && $SUDO dnf install quickshell (the installer does this unless --no-deps)" ;;
            arch)   note "quickshell: $SUDO pacman -S quickshell (or quickshell-git from the AUR for the newest)" ;;
            void)   note "quickshell: $SUDO xbps-install -S quickshell" ;;
            gentoo) note "quickshell: in GURU: $SUDO eselect repository enable guru && $SUDO emaint sync -r guru && $SUDO emerge --ask gui-apps/quickshell" ;;
            alpine) note "quickshell: not packaged for Alpine; build it from source: https://quickshell.org/docs/" ;;
            *)      note "quickshell is not in most distro repos, see https://quickshell.org/docs/ for your options" ;;
        esac
    fi
    # Void packages the whole desktop except the compositor itself.
    if has_item Hyprland "${missing[@]}" && [ "$FAMILY" = "void" ]; then
        printf '\n'
        note "Hyprland: not in Void's official repositories. The community repo is"
        note "  https://github.com/Makrennel/hyprland-void (xbps-src templates and binaries)"
    fi
    # Gentoo dropped Hyprland from the main tree; the old ::gentoo ebuild is
    # gone, not just masked, so `emerge hyprland` alone finds nothing.
    if has_item Hyprland "${missing[@]}" && [ "$FAMILY" = "gentoo" ]; then
        printf '\n'
        note "Hyprland: no longer in ::gentoo. It lives in the hyproverlay repository:"
        note "  $SUDO eselect repository enable hyproverlay && $SUDO emaint sync -r hyproverlay"
        note "  https://wiki.gentoo.org/wiki/Hyprland"
    fi
    # Alpine's stable repos stop short of these two; they live in edge/testing.
    if [ "$FAMILY" = "alpine" ]; then
        local -a alpine_testing=()
        has_item cava "${missing[@]}" && alpine_testing+=(cava)
        has_item cliphist "${missing[@]}" && alpine_testing+=(cliphist)
        if [ "${#alpine_testing[@]}" -gt 0 ]; then
            printf '\n'
            note "Alpine: ${alpine_testing[*]} are in edge/testing, not the stable repos."
            note "  https://dl-cdn.alpinelinux.org/alpine/edge/testing"
            note "Enable testing or build from source if you want those features."
        fi
    fi
    note "A missing tool degrades the one feature that uses it, not the session."
    STAGE_DETAIL="${#missing[@]} tools missing"
    return "$ST_WARN"
}

# Silhouette supports both systemd and OpenRC with first-class adaptation:
# power actions route through scripts/power.sh (systemctl vs loginctl/openrc-shutdown),
# user daemons (hypridle, hyprsunset, mpd) through scripts/user-service.sh,
# idle inhibition through scripts/inhibit.sh (systemd-inhibit vs elogind-inhibit),
# and session autostart through scripts/session-start.sh (D-Bus environment,
# pipewire audio stack on OpenRC, and hypridle).
stage_report_init() {
    local init pair svc level rc="$ST_OK"
    local -a todo=()

    if [ -d /run/systemd/system ]; then
        STAGE_DETAIL="systemd"
        return "$ST_OK"
    fi

    init="a non-systemd init"
    if [ -d /run/openrc ] || command -v openrc >/dev/null 2>&1; then
        init="OpenRC"
    fi
    STAGE_DETAIL="$init, first-class support"
    note "Silhouette automatically adapts: power actions route through elogind/loginctl,"
    note "inhibitors use elogind-inhibit, and daemons (hypridle, hyprsunset, mpd, pipewire)"
    note "are started and supervised cleanly via session-start.sh and user-service.sh."

    [ "$init" = "OpenRC" ] || return "$ST_OK"

    # service:runlevel. elogind provides the seat, logind API and loginctl
    # that Hyprland, the lockscreen and the polkit agent expect.
    for pair in elogind:boot dbus:default NetworkManager:default bluetooth:default; do
        svc="${pair%%:*}"
        level="${pair##*:}"
        [ -e "/etc/init.d/$svc" ] || continue
        compgen -G "/etc/runlevels/*/$svc" >/dev/null && continue
        todo+=("$SUDO rc-update add $svc $level")
    done
    if [ ! -e /etc/init.d/elogind ] && [ ! -e /etc/init.d/seatd ]; then
        printf '\n'
        warn "neither elogind nor seatd is installed; Hyprland needs one for seat access"
        note "$SUDO emerge --ask sys-auth/elogind  (and USE=elogind globally)"
        rc="$ST_WARN"
    fi
    if [ "${#todo[@]}" -gt 0 ]; then
        printf '\n'
        note "OpenRC services installed but not in any runlevel:"
        for pair in "${todo[@]}"; do
            dim "  $pair"
        done
        rc="$ST_WARN"
    fi
    return "$rc"
}

# The closing message after a successful install.
print_next_steps() {
    local hint self="${SCRIPT_DIR:-$SRC_DIR}/install.sh"

    printf '\n'
    if [ "$DRY_RUN" = "1" ]; then
        note "That was a dry run. Nothing was installed. Drop --dry-run to do it for real."
        return 0
    fi
    note "Configs are in $CONFIG_DIR, scripts are executable as shipped."
    note "Reload an existing session with Super + R, or log out and start Hyprland."
    note "Undo this install with: $self --rollback $STAMP"
    printf '\n'
    note "Optional tools this rice expects, install them if you want the feature:"
    for hint in "${OPTIONAL_HINTS[@]}"; do
        dim "  $hint"
    done
    if [ "$FAMILY" = "gentoo" ]; then
        dim "  Gentoo: both optional tools are in GURU, which is enabled now:"
        dim "  $SUDO emerge --ask --noreplace gui-apps/awww media-video/gpu-screen-recorder"
    fi
    if [ "$WANT_RISHOT" != "1" ]; then
        printf '\n'
        note "The rishot screenshot tool was not installed. To add it later, re-run with"
        note "--with-rishot, or run: curl -fsSL $RISHOT_URL | sh"
    fi
    return 0
}
