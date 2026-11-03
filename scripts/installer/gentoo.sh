# shellcheck shell=bash
# gentoo.sh: Gentoo is the one family where the installer writes the plan and
# you run it. USE flags, keywords and the decision to spend an hour compiling
# are yours, so nothing here feeds a list to emerge behind your back.

# Installed means a vdb entry: /var/db/pkg/<category>/<name>-<version>. Read
# straight from disk so this works without portage-utils or gentoolkit. The
# digit after the dash keeps kitty from matching kitty-shell-integration.
gentoo_installed() {
    local d
    for d in /var/db/pkg/"$1"-[0-9]*; do
        [ -d "$d" ] && return 0
    done
    return 1
}

gentoo_repo_enabled() {
    if command -v portageq >/dev/null 2>&1; then
        portageq get_repos / 2>/dev/null | tr ' ' '\n' | grep -qx -- "$1"
        return
    fi
    [ -d "/var/db/repos/$1" ]
}

# The keyword overlay packages need on this machine (~amd64, ~arm64, ...).
gentoo_arch() {
    local a=""
    command -v portageq >/dev/null 2>&1 && a="$(portageq envvar ARCH 2>/dev/null || true)"
    if [ -z "$a" ]; then
        case "$(uname -m)" in
            x86_64)  a="amd64" ;;
            aarch64) a="arm64" ;;
            i?86)    a="x86" ;;
            riscv64) a="riscv" ;;
            *)       a="$(uname -m)" ;;
        esac
    fi
    printf '%s' "$a"
}

# What it does: drop what is already installed, name the overlays that are
# missing, and print one command that is correct for this machine. Running it
# is a separate yes, and emerge --ask then asks a third time with the real plan.
#
# Returns a stage status: ST_OK (nothing needed, or emerge finished),
# ST_SKIP (the plan was printed for you to run), ST_WARN (emerge failed).
install_packages_gentoo() {
    local -a want=() repos=() overlay_atoms=()
    local atom repo arch lead=""

    for atom in "$@"; do
        gentoo_installed "$atom" && continue
        want+=("$atom")
        repo="${GENTOO_REPO_OF[$atom]:-}"
        [ -n "$repo" ] || continue
        overlay_atoms+=("$atom")
        if ! has_item "$repo" "${repos[@]}" && ! gentoo_repo_enabled "$repo"; then
            repos+=("$repo")
        fi
    done

    if [ "${#want[@]}" -eq 0 ]; then
        STAGE_DETAIL="all $# packages already installed"
        return "$ST_OK"
    fi

    note "Gentoo: ${#want[@]} of $# packages are not installed yet."
    note "Nothing is emerged for you; USE flags and keywords stay your call."

    if [ "${#repos[@]}" -gt 0 ]; then
        printf '\n'
        note "1. Enable the overlays these need:"
        gentoo_installed app-eselect/eselect-repository \
            || note "   $SUDO emerge --ask --noreplace app-eselect/eselect-repository"
        note "   $SUDO eselect repository enable ${repos[*]}"
        note "   $SUDO emaint sync$(printf -- ' -r %s' "${repos[@]}")"
    fi

    if [ "${#overlay_atoms[@]}" -gt 0 ]; then
        arch="$(gentoo_arch)"
        printf '\n'
        note "Overlay packages are usually keyworded ~$arch only. If you run stable,"
        note "accept them in /etc/portage/package.accept_keywords/silhouette:"
        for atom in "${overlay_atoms[@]}"; do
            dim "  $atom ~$arch"
        done
        if has_item gui-wm/hyprland "${overlay_atoms[@]}"; then
            note "Hyprland pulls in its own hypr* libraries from hyproverlay; emerge"
            note "--autounmask will list the extra keywords those need."
        fi
    fi

    printf '\n'
    [ "${#repos[@]}" -gt 0 ] && lead="2. "
    note "${lead}$SUDO emerge --ask --noreplace --verbose ${want[*]}"

    STAGE_DETAIL="${#want[@]} packages to emerge, plan printed"
    if [ "$DRY_RUN" = "1" ]; then
        DRY_SKIPPED=1
        return "$ST_SKIP"
    fi
    if [ "$ASSUME_YES" = "1" ]; then
        dim "--yes does not extend to emerge; run the command above when you are ready."
        return "$ST_SKIP"
    fi
    if [ "${#repos[@]}" -gt 0 ]; then
        dim "Enable the overlays first, then run the command above (or re-run this installer)."
        return "$ST_SKIP"
    fi
    if [ "$HAVE_PRIV" != "1" ]; then
        dim "No sudo or doas here: run the command above as root."
        return "$ST_SKIP"
    fi

    printf '\n'
    if ask_yn "    Run that emerge now? It shows its own plan and asks again before building." n; then
        # emerge --ask reads its answer from stdin, which is the script itself
        # under `curl | bash`; point it at the terminal.
        OUTSIDE_TXN_CHANGES=1
        if "$SUDO" emerge --ask --noreplace --verbose "${want[@]}" < /dev/tty; then
            STAGE_DETAIL="${#want[@]} packages emerged"
            return "$ST_OK"
        fi
        warn "emerge did not finish. The configs still deploy; re-run the command above when ready."
        STAGE_DETAIL="emerge did not finish"
        return "$ST_WARN"
    fi
    dim "skipped; the configs deploy either way"
    return "$ST_SKIP"
}
