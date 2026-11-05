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

# RetroArch, as a per-user Flatpak from Flathub. Per-user (--user) on purpose:
# no root, nothing touches the system, and it comes out with one command. flatpak
# itself is a core package, so this stage only needs it to be on PATH.
stage_retroarch() {
    if [ "$WANT_RETROARCH" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "flatpak remote-add --user --if-not-exists flathub $FLATHUB_URL"
        would_do run "flatpak install --user -y --noninteractive flathub $RETROARCH_ID"
        return "$ST_OK"
    fi
    if ! command -v flatpak >/dev/null 2>&1; then
        err "flatpak is not installed. It is in the core package list; check the package step,"
        err "or install it and re-run with --with-retroarch."
        return "$ST_FAIL"
    fi
    if flatpak info "$RETROARCH_ID" >/dev/null 2>&1; then
        STAGE_DETAIL="already installed"
        return "$ST_OK"
    fi

    OUTSIDE_TXN_CHANGES=1
    note "adding the Flathub remote (for your user only)"
    if ! flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL" < /dev/null; then
        err "could not add the Flathub remote (network?)"
        return "$ST_FAIL"
    fi
    note "installing $RETROARCH_ID from Flathub"
    if ! progress_run "Installing $RETROARCH_ID from Flathub" flatpak install --user -y --noninteractive flathub "$RETROARCH_ID"; then
        err "flatpak could not install $RETROARCH_ID"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="$RETROARCH_ID, user install"
    return "$ST_OK"
}

# Sioyek, as a per-user Flatpak from Flathub.
stage_sioyek() {
    if [ "$WANT_SIOYEK" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "flatpak remote-add --user --if-not-exists flathub $FLATHUB_URL"
        would_do run "flatpak install --user -y --noninteractive flathub $SIOYEK_ID"
        return "$ST_OK"
    fi
    if ! command -v flatpak >/dev/null 2>&1; then
        err "flatpak is not installed. It is in the core package list; check the package step,"
        err "or install it and re-run with --with-sioyek."
        return "$ST_FAIL"
    fi
    if flatpak info "$SIOYEK_ID" >/dev/null 2>&1; then
        STAGE_DETAIL="already installed"
        return "$ST_OK"
    fi

    OUTSIDE_TXN_CHANGES=1
    note "adding the Flathub remote (for your user only)"
    if ! flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL" < /dev/null; then
        err "could not add the Flathub remote (network?)"
        return "$ST_FAIL"
    fi
    note "installing $SIOYEK_ID from Flathub"
    if ! progress_run "Installing $SIOYEK_ID from Flathub" flatpak install --user -y --noninteractive flathub "$SIOYEK_ID"; then
        err "flatpak could not install $SIOYEK_ID"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="$SIOYEK_ID, user install"
    return "$ST_OK"
}

# Evangelion GRUB theme, cloned to ~/Projects/Evangelion and installed with SEELE theme.
stage_grub_theme() {
    local rc=0 installer eva_cmd

    if [ "$WANT_GRUB_THEME" != "1" ]; then
        STAGE_DETAIL="not requested"
        return "$ST_SKIP"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do run "git clone $EVA_REPO_URL $EVA_DIR"
        would_do run "cd $EVA_DIR && $SUDO ./bin/install.sh"
        would_do run "$SUDO eva set seele $GRUB_PROFILE"
        STAGE_DETAIL="dry run: Evangelion seele $GRUB_PROFILE"
        return "$ST_OK"
    fi

    if ! command -v git >/dev/null 2>&1; then
        err "git is needed to fetch the Evangelion GRUB theme"
        return "$ST_FAIL"
    fi

    mkdir -p "$(dirname -- "$EVA_DIR")"

    if [ -d "$EVA_DIR/.git" ]; then
        note "using existing Evangelion repository at $EVA_DIR"
    elif [ -d "$EVA_DIR" ]; then
        note "directory $EVA_DIR exists; using it"
    else
        note "cloning $EVA_REPO_URL into $EVA_DIR"
        if ! progress_run "Cloning Evangelion repository" git clone --depth 1 "$EVA_REPO_URL" "$EVA_DIR"; then
            err "could not clone $EVA_REPO_URL"
            return "$ST_FAIL"
        fi
    fi

    if [ ! -d "$EVA_DIR" ]; then
        err "Evangelion directory $EVA_DIR not found"
        return "$ST_FAIL"
    fi

    # Ensure installer scripts are executable
    chmod +x "$EVA_DIR/bin/install.sh" "$EVA_DIR/bin/eva" "$EVA_DIR/install.sh" 2>/dev/null || true

    OUTSIDE_TXN_CHANGES=1
    note "running Evangelion installer in $EVA_DIR"

    (
        cd -- "$EVA_DIR" || exit 1
        installer="./bin/install.sh"
        [ -f "$installer" ] || installer="./install.sh"

        if tty_available; then
            "$SUDO" "$installer" < /dev/tty || exit $?
        else
            "$SUDO" "$installer" < /dev/null || exit $?
        fi
    ) || rc=$?

    if [ "$rc" -ne 0 ]; then
        err "Evangelion install script exited with status $rc"
        return "$ST_FAIL"
    fi

    note "setting Evangelion theme to seele with profile $GRUB_PROFILE"
    eva_cmd="eva"
    if ! command -v eva >/dev/null 2>&1; then
        if [ -x "$EVA_DIR/bin/eva" ]; then
            eva_cmd="$EVA_DIR/bin/eva"
        fi
    fi

    if tty_available; then
        "$SUDO" $eva_cmd set seele "$GRUB_PROFILE" < /dev/tty || rc=$?
    else
        "$SUDO" $eva_cmd set seele "$GRUB_PROFILE" < /dev/null || rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        err "failed to set Evangelion seele theme ($GRUB_PROFILE)"
        return "$ST_FAIL"
    fi

    STAGE_DETAIL="seele, $GRUB_PROFILE"
    return "$ST_OK"
}
