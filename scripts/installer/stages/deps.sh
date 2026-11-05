# shellcheck shell=bash
# stages/deps.sh: packages. Best effort, and outside the config transaction:
# package names differ per distro and move between releases, so a failed batch
# is retried one package at a time and a name that does not resolve is reported,
# not fatal. A missing optional tool degrades one shell feature; it does not
# stop the install.

stage_bootstrap_tools() {
    local -a missing=() atoms=()
    local t

    if [ "$NO_DEPS" = "1" ]; then
        STAGE_DETAIL="--no-deps"
        return "$ST_SKIP"
    fi
    command -v git >/dev/null 2>&1 || missing+=(git)
    command -v python3 >/dev/null 2>&1 || missing+=(python3)
    if [ "${#missing[@]}" -eq 0 ]; then
        STAGE_DETAIL="git and python3 present"
        return "$ST_OK"
    fi

    note "installing bootstrap tools: ${missing[*]}"
    [ "$DRY_RUN" = "1" ] || OUTSIDE_TXN_CHANGES=1
    # These have the same name everywhere Silhouette claims to support.
    case "$PM" in
        dnf)    run "$SUDO" dnf install -y "${missing[@]}" || return "$ST_FAIL" ;;
        apk)    run "$SUDO" apk add --no-cache "${missing[@]}" || return "$ST_FAIL" ;;
        pacman) run "$SUDO" pacman -S --needed --noconfirm "${missing[@]}" || return "$ST_FAIL" ;;
        apt)    run "$SUDO" apt-get update && run "$SUDO" apt-get install -y "${missing[@]}" \
                    || return "$ST_FAIL" ;;
        zypper) run "$SUDO" zypper --non-interactive install "${missing[@]}" || return "$ST_FAIL" ;;
        xbps)   run "$SUDO" xbps-install -Sy "${missing[@]}" || return "$ST_FAIL" ;;
        emerge)
            # Portage needs python, so python3 missing here means a broken
            # eselect python target rather than a missing package.
            has_item git "${missing[@]}" && atoms+=(dev-vcs/git)
            has_item python3 "${missing[@]}" && atoms+=(dev-lang/python)
            gentoo_check_privilege || return "$ST_FAIL"
            gentoo_emerge "${atoms[@]}" || return "$ST_FAIL"
            has_item python3 "${missing[@]}" && note "if python is installed, check: eselect python list"
            ;;
        *)      err "need ${missing[*]} and do not know how to install it on this distro"
                return "$ST_FAIL" ;;
    esac

    if [ "$DRY_RUN" != "1" ]; then
        for t in "${missing[@]}"; do
            if ! command -v "$t" >/dev/null 2>&1; then
                err "$t is still missing after the install"
                return "$ST_FAIL"
            fi
        done
    fi
    STAGE_DETAIL="installed ${missing[*]}"
    return "$ST_OK"
}

stage_packages() {
    local -a pkgs=() skipped=()
    local p total

    if [ "$NO_DEPS" = "1" ]; then
        STAGE_DETAIL="--no-deps"
        return "$ST_SKIP"
    fi

    local -n core="CORE_${FAMILY}"
    pkgs=("${core[@]}")
    if [ "$FULL" = "1" ]; then
        local -n extra="FULL_${FAMILY}"
        pkgs+=("${extra[@]}")
    fi
    total="${#pkgs[@]}"

    if [ "$PM" = "emerge" ]; then
        install_packages_gentoo "${pkgs[@]}"
        return
    fi
    if [ -z "$PM" ]; then
        warn "unrecognised distro, install these yourself: ${pkgs[*]}"
        STAGE_DETAIL="unrecognised distro, $total packages listed"
        return "$ST_SKIP"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "$(pm_plan "${pkgs[@]}")"
        STAGE_DETAIL="$total packages"
        return "$ST_OK"
    fi

    note "installing $total packages with $PM"
    OUTSIDE_TXN_CHANGES=1
    if pm_install "${pkgs[@]}"; then
        STAGE_DETAIL="$total packages"
        return "$ST_OK"
    fi

    warn "the batch failed, retrying one at a time so one bad name does not sink the rest"
    if [ "$PM" = "xbps" ]; then
        note "Void: if xbps itself is out of date, run '$SUDO xbps-install -Suy xbps' first."
    fi
    for p in "${pkgs[@]}"; do
        if ! pm_install "$p"; then
            warn "skipped, not found in your repos: $p"
            skipped+=("$p")
        fi
    done

    if [ "${#skipped[@]}" -eq "$total" ]; then
        # Not one package installed: that is not a few wrong names, it is
        # something systemic (no network, sudo refused, repos not refreshed).
        err "no package could be installed; check that $SUDO works and the repos are reachable"
        STAGE_DETAIL="0 of $total installed"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="$((total - ${#skipped[@]})) installed, ${#skipped[@]} not found"
    return "$ST_WARN"
}

# Third-party repositories, enabled before the package step. Outside the config
# transaction like the packages themselves. Today only Fedora and Gentoo have any, through
# COPR (see COPR_fedora in packages.sh), and Gentoo, through its overlays
# (gentoo.sh); a failure is a setback, not a stop: the
# packages stage retries per package and reports whatever does not resolve.
stage_repos() {
    local r
    local -a failed=()

    if [ "$NO_DEPS" = "1" ]; then
        STAGE_DETAIL="--no-deps"
        return "$ST_SKIP"
    fi
    if [ "$PM" = "emerge" ]; then
        gentoo_enable_repos
        return
    fi
    if [ "$PM" != "dnf" ] || ! declare -p "COPR_${FAMILY}" >/dev/null 2>&1; then
        STAGE_DETAIL="none needed for ${FAMILY}"
        return "$ST_SKIP"
    fi
    local -n repos="COPR_${FAMILY}"

    [ "$DRY_RUN" = "1" ] || OUTSIDE_TXN_CHANGES=1
    if ! dnf_copr_ready; then
        err "'dnf copr' is not available and could not be installed (dnf-plugins-core / dnf5-plugins)"
        return "$ST_FAIL"
    fi
    for r in "${repos[@]}"; do
        note "enabling COPR $r"
        if ! run "$SUDO" dnf copr enable -y "$r"; then
            warn "could not enable $r"
            failed+=("$r")
        fi
    done

    if [ "${#failed[@]}" -eq "${#repos[@]}" ]; then
        err "no COPR repository could be enabled"
        return "$ST_FAIL"
    fi
    if [ "${#failed[@]}" -gt 0 ]; then
        STAGE_DETAIL="$((${#repos[@]} - ${#failed[@]})) enabled; failed: ${failed[*]}"
        return "$ST_WARN"
    fi
    STAGE_DETAIL="${repos[*]}"
    return "$ST_OK"
}

# hyprctl ships inside the compositor package, on every distro; there is no
# separate package to install. So "have hyprctl" means "the compositor package
# landed". Verify it, and if it did not, try that one package again on its own.
stage_hyprctl() {
    local pkg="${HYPRLAND_PKG[$FAMILY]:-}"

    if [ "$DRY_RUN" = "1" ]; then
        STAGE_DETAIL="provided by ${pkg:-no package on $FAMILY}"
        return "$ST_OK"
    fi
    if command -v hyprctl >/dev/null 2>&1; then
        STAGE_DETAIL="found at $(command -v hyprctl)"
        return "$ST_OK"
    fi

    # One targeted retry. Gentoo stays advisory (nothing is emerged unasked),
    # and with --no-deps no package is touched.
    if [ -n "$pkg" ] && [ -n "$PM" ] && [ "$PM" != "emerge" ] && [ "$NO_DEPS" != "1" ]; then
        note "hyprctl is missing; retrying $pkg on its own"
        OUTSIDE_TXN_CHANGES=1
        if pm_install "$pkg" && command -v hyprctl >/dev/null 2>&1; then
            STAGE_DETAIL="installed with $pkg"
            return "$ST_OK"
        fi
    fi

    warn "hyprctl is not on PATH"
    note "It is part of the compositor package (${pkg:-not packaged for $FAMILY}), not a separate one."
    case "$FAMILY" in
        void)   note "Void has no official Hyprland: https://github.com/Makrennel/hyprland-void" ;;
        gentoo) note "$SUDO emerge --ask gui-wm/hyprland   (hyproverlay must be enabled first)" ;;
        fedora) note "Check: $SUDO dnf copr list; then $SUDO dnf install hyprland-git" ;;
    esac
    STAGE_DETAIL="not found"
    return "$ST_WARN"
}
