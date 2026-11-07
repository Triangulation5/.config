# shellcheck shell=bash
# gentoo.sh: the Gentoo flow. Unattended, and built around three facts:
#
#   1. Hyprland, quickshell, brightnessctl, cliphist and yazi are not in the
#      main tree. They live in two overlays: hyproverlay (Hyprland) and GURU
#      (the rest). Both are enabled with eselect-repository and synced.
#   2. Third-party repositories have no stable keyword, so their packages are
#      masked until accepted. The Gentoo wiki's own answer is a repo-wide
#      `*/*::hyproverlay` in /etc/portage/package.accept_keywords; the same is
#      written for guru. Transitive keyword/USE changes are left to emerge's
#      --autounmask-continue, and the config updates it writes are merged with
#      `etc-update --automode -5 /etc/portage`, scoped to that directory.
#   3. emerge fails the WHOLE command on one atom that does not exist, and
#      package names drift (app-arch/p7zip was removed in 2026). So every atom is
#      checked with portageq first; one that does not resolve is reported and
#      left out, the way the other distros skip a name their repos lack.
#
# Everything here runs as root through gentoo_root (sudo, doas, or su when
# neither exists). It is outside the config transaction.
#
# These functions return stage statuses (ST_OK, ST_WARN, ...).

GENTOO_OVERLAYS=(hyproverlay guru)

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

# Does this atom resolve to a visible ebuild right now (repos enabled and synced,
# keywords accepted)? best_visible exits non-zero and prints nothing if not.
gentoo_atom_available() {
    local out
    out="$(portageq best_visible / "$1" 2>/dev/null)" || return 1
    [ -n "$out" ]
}

# Run a command as root. Uses priv_run (sudo, doas, or su).
gentoo_root() {
    priv_run "$@"
}

# Can root be reached at all? (the check itself is priv_check, in distro.sh)
gentoo_check_privilege() { priv_check; }

# The one emerge invocation every install uses.
#   --ask=n                 beats an EMERGE_DEFAULT_OPTS that says --ask
#   --keep-going            a package that fails to build does not sink the rest
#   --autounmask* =y        keyword/USE/license changes the dependency graph
#                           needs are applied, and written to /etc/portage
gentoo_emerge() {
    local label="Emerging ${#} package(s)"
    # Quiet when no password prompt can appear: a hours-long build shows one live
    # line (">>> Emerging (3 of 20) ..." from emerge's own log) instead of a wall
    # of compiler output; the full log stays on disk. Otherwise plainly.
    priv_progress "$label" emerge --ask=n --noreplace --verbose --keep-going \
        --autounmask=y --autounmask-write=y --autounmask-continue=y "$@"
}

# Autounmask writes its changes as ._cfgNNNN_ files because /etc is
# CONFIG_PROTECTed. Merge those, and only those under /etc/portage.
gentoo_merge_portage_config() {
    [ "$DRY_RUN" = "1" ] && return 0
    if find /etc/portage -name '._cfg*' -print -quit 2>/dev/null | grep -q .; then
        note "merging the keyword/USE changes emerge wrote to /etc/portage"
        gentoo_root etc-update --automode -5 /etc/portage < /dev/null \
            || warn "etc-update could not merge /etc/portage; run: etc-update /etc/portage"
    fi
    return 0
}

# Accept the testing keyword for the overlays. package.accept_keywords may be a
# directory (the usual layout) or a single file; handle both. Idempotent.
gentoo_accept_overlay_keywords() {
    local base=/etc/portage/package.accept_keywords tmp repo added=0
    local -a lines=()
    for repo in "${GENTOO_OVERLAYS[@]}"; do lines+=("*/*::$repo"); done

    if [ "$DRY_RUN" = "1" ]; then
        would_do write "${lines[*]} to $base/silhouette"
        return 0
    fi

    tmp="$(mktemp)" || return 1
    temp_register "$tmp"

    if [ -f "$base" ]; then
        # A single-file layout: append whatever is missing.
        cp -- "$base" "$tmp" || return 1
        for repo in "${lines[@]}"; do
            if ! grep -qxF -- "$repo" "$base"; then
                printf '%s\n' "$repo" >> "$tmp"
                added=1
            fi
        done
        [ "$added" = "0" ] && return 0
        gentoo_root install -m 0644 -- "$tmp" "$base"
        return
    fi

    # Directory layout: one file of our own.
    {
        printf '%s\n' "# Written by the Silhouette installer. Third-party repositories carry no"
        printf '%s\n' "# stable keyword, so accept the testing keyword for the two overlays its"
        printf '%s\n' "# packages come from (Hyprland: hyproverlay; quickshell and friends: guru)."
        printf '%s\n' "${lines[@]}"
    } > "$tmp"
    if [ -f "$base/silhouette" ] && cmp -s -- "$tmp" "$base/silhouette"; then
        return 0
    fi
    if [ ! -d "$base" ]; then
        gentoo_root install -d -m 0755 -- "$base" || return 1
    fi
    gentoo_root install -m 0644 -- "$tmp" "$base/silhouette"
}

# stage_repos for Gentoo: eselect-repository and git, the two overlays, a sync,
# and the keywords that make the overlays' packages visible.
gentoo_enable_repos() {
    local repo
    local -a need=() tools=() sync_args=()

    gentoo_check_privilege || return "$ST_FAIL"
    [ "$DRY_RUN" = "1" ] || OUTSIDE_TXN_CHANGES=1

    for repo in "${GENTOO_OVERLAYS[@]}"; do
        gentoo_repo_enabled "$repo" || need+=("$repo")
    done

    if [ "${#need[@]}" -gt 0 ]; then
        gentoo_installed app-eselect/eselect-repository || tools+=(app-eselect/eselect-repository)
        # eselect repository syncs overlays with git.
        gentoo_installed dev-vcs/git || tools+=(dev-vcs/git)
        if [ "${#tools[@]}" -gt 0 ]; then
            note "installing ${tools[*]} (needed to add overlays)"
            if ! gentoo_emerge "${tools[@]}"; then
                err "could not emerge ${tools[*]}"
                return "$ST_FAIL"
            fi
        fi

        note "enabling overlays: ${need[*]}"
        if ! gentoo_root eselect repository enable "${need[@]}"; then
            err "eselect repository enable ${need[*]} failed"
            return "$ST_FAIL"
        fi
        for repo in "${need[@]}"; do
            note "syncing overlay $repo"
            if ! priv_progress "Syncing overlay $repo" emaint sync -r "$repo"; then
                err "emaint sync -r $repo failed (network?)"
                return "$ST_FAIL"
            fi
        done
    fi

    if ! gentoo_accept_overlay_keywords; then
        err "could not write the overlay keywords to /etc/portage/package.accept_keywords"
        return "$ST_FAIL"
    fi

    if [ "${#need[@]}" -gt 0 ]; then
        STAGE_DETAIL="enabled and synced ${need[*]}"
    else
        STAGE_DETAIL="${GENTOO_OVERLAYS[*]} already enabled"
    fi
    return "$ST_OK"
}

# stage_packages for Gentoo.
#   ST_OK    everything is installed
#   ST_WARN  some are, the rest are listed with the command to retry them
#   ST_FAIL  nothing could be installed
install_packages_gentoo() {
    local atom total="$#" ok
    local -a want=() avail=() unavailable=() failed=()

    for atom in "$@"; do
        gentoo_installed "$atom" || want+=("$atom")
    done
    if [ "${#want[@]}" -eq 0 ]; then
        STAGE_DETAIL="all $total packages already installed"
        return "$ST_OK"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        # Repos are not enabled in a dry run, so availability cannot be judged.
        gentoo_emerge "${want[@]}"
        STAGE_DETAIL="${#want[@]} of $total packages to emerge"
        return "$ST_OK"
    fi

    gentoo_check_privilege || return "$ST_FAIL"

    for atom in "${want[@]}"; do
        if gentoo_atom_available "$atom"; then
            avail+=("$atom")
        else
            unavailable+=("$atom")
            warn "not found in any enabled repository, skipping: $atom"
        fi
    done
    if [ "${#avail[@]}" -eq 0 ]; then
        err "none of the packages resolve; are the overlays synced? Try: emaint sync -a"
        STAGE_DETAIL="nothing resolved"
        return "$ST_FAIL"
    fi

    note "emerging ${#avail[@]} packages. They compile from source, so this can take a long time."
    OUTSIDE_TXN_CHANGES=1
    gentoo_emerge "${avail[@]}" || warn "emerge reported failures; checking what did get installed"
    gentoo_merge_portage_config

    for atom in "${avail[@]}"; do
        gentoo_installed "$atom" || failed+=("$atom")
    done

    ok=$(( ${#avail[@]} - ${#failed[@]} ))
    if [ "${#failed[@]}" -eq 0 ] && [ "${#unavailable[@]}" -eq 0 ]; then
        STAGE_DETAIL="$ok packages emerged"
        return "$ST_OK"
    fi
    if [ "$ok" -eq 0 ]; then
        err "no package was installed; the emerge output above says why"
        STAGE_DETAIL="0 of ${#want[@]} installed"
        return "$ST_FAIL"
    fi
    if [ "${#failed[@]}" -gt 0 ]; then
        warn "did not build: ${failed[*]}"
        note "retry with: $SUDO emerge --ask --noreplace --autounmask-continue ${failed[*]}"
    fi
    STAGE_DETAIL="$ok installed, $(( ${#failed[@]} + ${#unavailable[@]} )) not"
    return "$ST_WARN"
}
