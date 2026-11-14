# shellcheck shell=bash
# stages/extras.sh: optional third-party tools. Outside the config transaction:
# these are other projects' installers, and this installer cannot undo what
# they do. They run after the commit, so a failure here never rolls back the
# dotfiles.

# rishot is installed by running its own installer:
#
#     curl -fsSL <RISHOT_URL> | sh
#
# That is what this stage runs, with one difference: the script is downloaded
# to a file first and run from there. Piping curl into sh starts executing
# while the download is still arriving, so a dropped connection can run a
# truncated script. A file that downloaded completely either runs whole or
# not at all, and a failed download is reported as a failed download.
stage_rishot() {
    local tmp bytes sum="" rc=0

    if [ "$WANT_RISHOT" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "curl -fsSL $RISHOT_URL | sh"
        return "$ST_OK"
    fi
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is needed to fetch the rishot installer"
        return "$ST_FAIL"
    fi

    tmp="$(mktemp)" || { err "could not create a temporary file"; return "$ST_FAIL"; }
    temp_register "$tmp"

    note "downloading $RISHOT_URL"
    if ! curl -fsSL --retry 2 -o "$tmp" -- "$RISHOT_URL"; then
        err "could not download the rishot installer"
        return "$ST_FAIL"
    fi
    bytes="$(wc -c < "$tmp" | tr -d ' ')"
    if [ "${bytes:-0}" -eq 0 ]; then
        err "the rishot installer downloaded empty"
        return "$ST_FAIL"
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        sum="$(sha256sum "$tmp" | cut -c1-16)"
    fi
    dim "$bytes bytes${sum:+, sha256 $sum...}; running it with sh"

    OUTSIDE_TXN_CHANGES=1
    # Its stdin is the terminal when there is one, so any question it asks
    # reaches you; otherwise it gets none rather than ours.
    if tty_available; then
        sh "$tmp" < /dev/tty || rc=$?
    else
        sh "$tmp" < /dev/null || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        err "the rishot installer exited with status $rc"
        return "$ST_FAIL"
    fi

    if command -v rishot >/dev/null 2>&1; then
        STAGE_DETAIL="installed"
        return "$ST_OK"
    fi
    warn "its installer finished, but rishot is not on PATH yet"
    note "open a new shell, or look for where that installer put it."
    STAGE_DETAIL="installed, not on PATH yet"
    return "$ST_WARN"
}

# Flatpak apps from Flathub: Sioyek (on by default) and RetroArch (opt-in).
# Per-user installs (--user) on purpose: no root, nothing touches the system, and
# each comes out with one command. flatpak itself is a core package, so this
# stage only needs it on PATH. The Flathub remote is added once, for both.
#
# WANT_SIOYEK is 1 (asked for), 0 (declined) or auto (nobody asked, so the
# default applies). With auto and no flatpak the stage skips quietly: a default
# should not turn a --no-deps run into a [ Failed ] and an exit status of 3.
#
# Sioyek's Flathub build is granted ~/.config/sioyek and Documents only, so the
# deployed sioyek config is picked up as it is; PDFs elsewhere need an override
# (printed at the end).
stage_flatpaks() {
    local id remote_done=0
    local -a apps=() installed=() failed=()

    case "$WANT_SIOYEK" in 1|auto) apps+=("$SIOYEK_ID") ;; esac
    if [ "$WANT_RETROARCH" = "1" ]; then apps+=("$RETROARCH_ID"); fi
    if [ "${#apps[@]}" -eq 0 ]; then
        STAGE_DETAIL="none requested"
        return "$ST_SKIP"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do run "flatpak remote-add --user --if-not-exists flathub $FLATHUB_URL"
        for id in "${apps[@]}"; do
            would_do run "flatpak install --user -y --noninteractive flathub $id"
        done
        STAGE_DETAIL="${apps[*]}"
        return "$ST_OK"
    fi

    if ! command -v flatpak >/dev/null 2>&1; then
        if [ "${#apps[@]}" -eq 1 ] && [ "$WANT_SIOYEK" = "auto" ]; then
            STAGE_DETAIL="flatpak is not installed, so Sioyek was skipped"
            return "$ST_SKIP"
        fi
        err "flatpak is not installed. It is in the core package list; check the package step,"
        err "or install it and re-run with --with-sioyek / --with-retroarch."
        return "$ST_FAIL"
    fi

    for id in "${apps[@]}"; do
        if flatpak info "$id" >/dev/null 2>&1; then
            installed+=("$id")
            dim "already installed: $id"
            continue
        fi
        OUTSIDE_TXN_CHANGES=1
        if [ "$remote_done" = "0" ]; then
            note "adding the Flathub remote (for your user only)"
            if ! flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL" < /dev/null; then
                err "could not add the Flathub remote (network?)"
                return "$ST_FAIL"
            fi
            remote_done=1
        fi
        note "installing $id from Flathub"
        if progress_run "Installing $id from Flathub" \
               flatpak install --user -y --noninteractive flathub "$id"; then
            installed+=("$id")
        else
            err "flatpak could not install $id"
            failed+=("$id")
        fi
    done

    if [ "${#failed[@]}" -eq 0 ]; then
        STAGE_DETAIL="${installed[*]}"
        return "$ST_OK"
    fi
    if [ "${#installed[@]}" -eq 0 ]; then
        STAGE_DETAIL="failed: ${failed[*]}"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="installed ${installed[*]}; failed ${failed[*]}"
    return "$ST_WARN"
}

# ---- Evangelion GRUB theme -----------------------------------------------------
#
# This changes the bootloader, so it is the most careful stage in the installer:
#
#   * It only runs where GRUB 2 is actually in use. The themes are GRUB-only.
#   * It runs a third party's script as root, so it is pinned to a release tag
#     (EVA_REF), not whatever is on the default branch today, and it says which
#     commit it is running.
#   * Upstream's install.sh is interactive (it asks for a theme and a profile).
#     The profile was already chosen in the plan, so it is run with --no-apply,
#     which installs the `eva` command and the theme catalog without applying
#     anything, and the theme is then applied directly with `eva set`. You are
#     asked once, not twice.
#   * /etc/default/grub is copied into the run's backup directory first. The
#     config transaction does not cover the bootloader; `sudo eva uninstall`
#     (upstream's own undo) does.

# GRUB 2 present: its directory, and the tool that regenerates its config.
grub_present() {
    { [ -d /boot/grub ] || [ -d /boot/grub2 ]; } || return 1
    command -v grub-mkconfig >/dev/null 2>&1 || command -v grub2-mkconfig >/dev/null 2>&1
}

# Get EVA_DIR to the pinned tag: clone it, or move an existing clone onto it.
eva_fetch_repo() {
    if [ ! -e "$EVA_DIR" ]; then
        mkdir -p -- "$(dirname -- "$EVA_DIR")" || return 1
        note "cloning $EVA_REPO_URL ($EVA_REF) into $EVA_DIR"
        # No git credential prompt: it would be hidden behind the spinner.
        progress_run "Cloning Evangelion $EVA_REF" \
            env GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 --branch "$EVA_REF" \
                -- "$EVA_REPO_URL" "$EVA_DIR"
        return
    fi
    if [ -d "$EVA_DIR/.git" ]; then
        note "checking out pinned Evangelion release $EVA_REF"
        if progress_run "Fetching Evangelion $EVA_REF" \
               env GIT_TERMINAL_PROMPT=0 git -C "$EVA_DIR" fetch --quiet --depth 1 origin \
                   "refs/tags/$EVA_REF:refs/tags/$EVA_REF" \
           && git -C "$EVA_DIR" checkout --quiet --detach "$EVA_REF"; then
               if [ -z "$(git -C "$EVA_DIR" status --porcelain)" ]; then
                   return 0
               fi
               err "$EVA_DIR has local changes; refusing to run an unverified installer as root"
               return 1
        fi
        err "could not check out pinned release $EVA_REF in $EVA_DIR; refusing to run its installer as root"
        return 1
    fi
    err "$EVA_DIR exists and is not a git checkout; move it away or remove it"
    return 1
}

stage_grub_theme() {
    local rev="" bk="$BACKUP_DIR/grub" rc=0

    if [ "$WANT_GRUB_THEME" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi
    if ! grub_present; then
        warn "GRUB 2 was not found (no /boot/grub or /boot/grub2, or no grub-mkconfig)."
        note "The Evangelion themes are GRUB 2 only, so nothing was changed."
        STAGE_DETAIL="GRUB not detected"
        return "$ST_WARN"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do run "git clone --depth 1 --branch $EVA_REF $EVA_REPO_URL $EVA_DIR"
        would_do run "cp /etc/default/grub $bk/default-grub"
        would_do run "cd $EVA_DIR && $SUDO ./install.sh --no-apply"
        would_do run "$SUDO eva set seele $GRUB_PROFILE"
        STAGE_DETAIL="SEELE $GRUB_PROFILE, $EVA_REF"
        return "$ST_OK"
    fi

    if ! command -v git >/dev/null 2>&1; then
        err "git is needed to fetch the Evangelion GRUB theme"
        return "$ST_FAIL"
    fi
    priv_check || return "$ST_FAIL"

    # A copy of the one file the theme installer edits, before anything runs.
    if ! mkdir -p -- "$bk"; then
        err "could not create $bk; not touching the bootloader"
        return "$ST_FAIL"
    fi
    if [ -f /etc/default/grub ] && ! cp -p -- /etc/default/grub "$bk/default-grub"; then
        err "could not save /etc/default/grub to $bk; not touching the bootloader"
        return "$ST_FAIL"
    fi
    note "saved /etc/default/grub to $bk"

    eva_fetch_repo || return "$ST_FAIL"
    if [ ! -f "$EVA_DIR/install.sh" ]; then
        err "$EVA_DIR/install.sh not found; is that the Evangelion repository?"
        return "$ST_FAIL"
    fi
    rev="$(git -C "$EVA_DIR" describe --tags --always 2>/dev/null || true)"

    OUTSIDE_TXN_CHANGES=1
    note "running Evangelion ${rev:-$EVA_REF} as root (this edits your GRUB configuration)"
    # Its stdin is the terminal when there is one, so a sudo password prompt or
    # a question from the installer can be answered; otherwise it gets none.
    if tty_available; then
        ( cd -- "$EVA_DIR" && priv_run ./install.sh --no-apply < /dev/tty ) || rc=$?
    else
        ( cd -- "$EVA_DIR" && priv_run ./install.sh --no-apply < /dev/null ) || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        err "the Evangelion installer exited with status $rc"
        note "Nothing was applied. /etc/default/grub is saved in $bk"
        return "$ST_FAIL"
    fi

    note "applying SEELE ($GRUB_PROFILE)"
    if tty_available; then
        priv_run eva set seele "$GRUB_PROFILE" < /dev/tty || rc=$?
    else
        priv_run eva set seele "$GRUB_PROFILE" < /dev/null || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        err "could not apply the SEELE theme (status $rc)"
        note "Try it by hand: $SUDO eva set seele $GRUB_PROFILE      (list: eva list)"
        note "Undo anything it changed with: $SUDO eva uninstall"
        return "$ST_FAIL"
    fi

    STAGE_DETAIL="SEELE $GRUB_PROFILE, ${rev:-$EVA_REF}"
    return "$ST_OK"
}

# Helper to locate staged installer scripts across various execution layouts
find_installer_stage_script() {
    local name="$1" d
    for d in \
        "${INSTALLER_DIR:-}/stages" \
        "$(dirname "${BASH_SOURCE[0]}")" \
        "${SRC_DIR:-}/scripts/installer/stages" \
        "${SRC_DIR:-}/installer/stages" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/scripts/installer/stages"; do
        if [ -n "$d" ] && [ -f "$d/$name" ]; then
            printf '%s' "$d/$name"
            return 0
        fi
    done
    return 1
}

# ---- Pi agent harness -----------------------------------------------------------
stage_pi_harness() {
    local script rc=0
    if [ "$WANT_PI_HARNESS" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do run "stages/harness.sh install"
        STAGE_DETAIL="dry run"
        return "$ST_OK"
    fi

    if ! script="$(find_installer_stage_script "harness.sh")"; then
        err "could not find stages/harness.sh"
        return "$ST_FAIL"
    fi

    OUTSIDE_TXN_CHANGES=1
    note "running Pi agent harness installer ($script)"
    if tty_available; then
        bash "$script" install < /dev/tty || rc=$?
    else
        bash "$script" install < /dev/null || rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        err "the Pi agent harness installer exited with status $rc"
        return "$ST_FAIL"
    fi

    STAGE_DETAIL="installed"
    return "$ST_OK"
}

# ---- Ollama setup & model selector ---------------------------------------------
stage_ollama() {
    local script rc=0
    if [ "$WANT_OLLAMA" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do run "stages/ollama.sh --dry-run"
        STAGE_DETAIL="dry run"
        return "$ST_OK"
    fi

    if ! script="$(find_installer_stage_script "ollama.sh")"; then
        err "could not find stages/ollama.sh"
        return "$ST_FAIL"
    fi

    OUTSIDE_TXN_CHANGES=1
    note "running Ollama setup script ($script)"
    local -a args=()
    if [ "$ASSUME_YES" = "1" ]; then
        args+=("--yes")
    fi

    if tty_available; then
        bash "$script" "${args[@]}" < /dev/tty || rc=$?
    else
        bash "$script" "${args[@]}" < /dev/null || rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        err "the Ollama setup script exited with status $rc"
        return "$ST_FAIL"
    fi

    STAGE_DETAIL="completed"
    return "$ST_OK"
}

# ---- custom Simple Terminal (st) ----------------------------------------------
# Cloned to ST_DIR and built with make; `make install` needs root. kitty stays
# installed (the deployed configs use it); st is an extra choice.
st_build_deps() {
    case "$PM" in
        emerge) echo "x11-libs/libX11 x11-libs/libXft media-libs/fontconfig media-libs/freetype sys-libs/ncurses" ;;
        dnf)    echo "gcc make pkgconf-pkg-config libX11-devel libXft-devel fontconfig-devel freetype-devel ncurses" ;;
        pacman) echo "base-devel libx11 libxft fontconfig freetype2 ncurses" ;;
        apt)    echo "build-essential pkg-config libx11-dev libxft-dev libfontconfig1-dev libfreetype-dev ncurses-bin" ;;
        zypper) echo "gcc make pkg-config libX11-devel libXft-devel fontconfig-devel freetype2-devel ncurses-utils" ;;
        apk)    echo "build-base pkgconf libx11-dev libxft-dev fontconfig-dev freetype-dev ncurses" ;;
        xbps)   echo "base-devel pkg-config libX11-devel libXft-devel fontconfig-devel freetype-devel ncurses" ;;
        *)      echo "" ;;
    esac
}

stage_st() {
    local deps

    if [ "$TERMINAL_CHOICE" != "st" ]; then
        STAGE_DETAIL="kitty selected"
        return "$ST_SKIP"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "git clone --depth 1 $ST_REPO_URL $ST_DIR"
        would_do run "make -C $ST_DIR && $SUDO make -C $ST_DIR install"
        return "$ST_OK"
    fi
    if ! command -v git >/dev/null 2>&1; then
        err "git is needed to fetch st"
        return "$ST_FAIL"
    fi

    deps="$(st_build_deps)"
    if [ "$NO_DEPS" != "1" ] && [ -n "$deps" ] && [ -n "$PM" ]; then
        if [ "$PM" = "emerge" ]; then
            local -a atoms=()
            read -r -a atoms <<< "$deps"
            install_packages_gentoo "${atoms[@]}" \
                || warn "could not install every st build dependency; the build may fail"
        else
            # shellcheck disable=SC2086
            progress_run "Installing st build dependencies" pm_install $deps \
                || warn "could not install every st build dependency; the build may fail"
        fi
    fi

    if [ ! -e "$ST_DIR" ]; then
        mkdir -p -- "$(dirname -- "$ST_DIR")" || return "$ST_FAIL"
        progress_run "Cloning st" \
            env GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 -- "$ST_REPO_URL" "$ST_DIR" \
            || { err "could not clone $ST_REPO_URL"; return "$ST_FAIL"; }
    elif [ -d "$ST_DIR/.git" ]; then
        progress_run "Updating st" env GIT_TERMINAL_PROMPT=0 git -C "$ST_DIR" pull --quiet --ff-only \
            || warn "could not update $ST_DIR; building it as it is"
    else
        err "$ST_DIR exists and is not a git checkout; move it away or remove it"
        return "$ST_FAIL"
    fi

    progress_run "Building st" make -C "$ST_DIR" \
        || { err "st failed to build (see the log); build deps may be missing"; return "$ST_FAIL"; }
    OUTSIDE_TXN_CHANGES=1
    priv_run make -C "$ST_DIR" install \
        || { err "make install failed for st"; return "$ST_FAIL"; }
    STAGE_DETAIL="installed to /usr/local/bin/st"
    return "$ST_OK"
}
