# shellcheck shell=bash
# stages/plan.sh: interview, then plan, then one confirmation.
#
# Everything the user gets a say in is asked here, before anything changes, so
# the plan that is confirmed is the plan that runs. Answers land in FULL,
# KEEP_MONITORS and WANT_RISHOT. A flag already answered a question; with no
# terminal (or --yes) a question takes its default.

stage_plan() {
    local rc=0 pkgline monline rishotline shellline retroline sioyekline grubline cur

    if interactive; then
        say ""
        note "A few questions first. Enter takes the answer in brackets."

        if [ "$NO_DEPS" != "1" ] && [ -z "$FULL" ]; then
            if ask_yn "    Install the daily apps too (file manager, browser, yazi's preview helpers)?" n; then
                FULL=1
            else
                FULL=0
            fi
        fi

        if [ -z "$KEEP_MONITORS" ] && [ -f "$SRC_DIR/hypr/modules/monitors.lua" ]; then
            note "The repo ships the author's monitor layout. A portable default uses each"
            note "screen's preferred mode; the original is kept as monitors.lua.example."
            if ask_yn "    Use the portable monitor layout?" y; then
                KEEP_MONITORS=0
            else
                KEEP_MONITORS=1
            fi
        fi

        if [ -z "$SHELL_CHOICE" ]; then
            cur="$(current_shell)"
            note "Shell: you are using $cur. The configs for bash and zsh are both deployed."
            note "Switching your login shell is never done for you; the steps are printed at the end."
            ask_choice "    Install [b]ash, install [z]sh, or [k]eep what you have? [k]" k b z k
            case "$CHOICE" in
                b) SHELL_CHOICE=bash ;;
                z) SHELL_CHOICE=zsh ;;
                *) SHELL_CHOICE=keep ;;
            esac
        fi

        if [ -z "$WANT_SIOYEK" ]; then
            note "Sioyek is a PDF reader focused on research papers, books, and"
            note "technical documents. Installs as a user Flatpak"
            note "($SIOYEK_ID from Flathub); no root needed, and flatpak itself is core."
            if ask_yn "    Install Sioyek?" y; then
                WANT_SIOYEK=1
            else
                WANT_SIOYEK=0
            fi
        fi

        if [ -z "$WANT_RETROARCH" ]; then
            note "RetroArch is a game emulator front end. Installs as a user Flatpak"
            note "($RETROARCH_ID from Flathub); no root needed, and flatpak itself is core."
            if ask_yn "    Install RetroArch?" n; then
                WANT_RETROARCH=1
            else
                WANT_RETROARCH=0
            fi
        fi

        if [ -z "$WANT_GRUB_THEME" ]; then
            if grub_present; then
                note "Evangelion GRUB theme ($EVA_REPO_URL, release $EVA_REF)."
                note "This edits your bootloader configuration (/etc/default/grub and /boot). A copy of"
                note "that file is saved first, and 'sudo eva uninstall' puts the old theme back."
                if ask_yn "    Install the Evangelion GRUB theme?" n; then
                    WANT_GRUB_THEME=1
                else
                    WANT_GRUB_THEME=0
                fi
            else
                WANT_GRUB_THEME=0
                dim "GRUB 2 was not found on this machine, so the GRUB theme is not offered."
            fi
        fi

        if [ "$WANT_GRUB_THEME" = "1" ] && [ -z "$GRUB_PROFILE" ]; then
            say ""
            say "    Choose a display profile:"
            say "      1) 720p  1280x720"
            say "      2) 1080p  1920x1080"
            say "      3) 1440p  2560x1440 and larger"
            ask_choice "    Select profile [1-3]? [2]" 2 1 2 3
            case "$CHOICE" in
                1) GRUB_PROFILE="720p" ;;
                3) GRUB_PROFILE="1440p" ;;
                *) GRUB_PROFILE="1080p" ;;
            esac
        fi

        if [ -z "$WANT_RISHOT" ]; then
            note "rishot is a screenshot tool with its own installer. It is a separate"
            note "project: this would download and run $RISHOT_URL"
            if ask_yn "    Install rishot?" n; then
                WANT_RISHOT=1
            else
                WANT_RISHOT=0
            fi
        fi
    fi

    # Defaults for anything still undecided: the conservative answer.
    : "${FULL:=0}"
    : "${KEEP_MONITORS:=0}"
    : "${WANT_RISHOT:=0}"
    : "${WANT_RETROARCH:=0}"
    : "${WANT_SIOYEK:=auto}"
    : "${WANT_GRUB_THEME:=0}"
    : "${GRUB_PROFILE:=1080p}"
    : "${SHELL_CHOICE:=keep}"

    if [ "$NO_DEPS" = "1" ]; then
        pkgline="skipped (--no-deps)"
    elif [ "$PM" = "emerge" ]; then
        pkgline="emerge from ::gentoo plus the guru and hyproverlay overlays, which are enabled and synced first;"
        pkgline="$pkgline their keywords go to /etc/portage/package.accept_keywords. Compiles from source:"
        pkgline="$pkgline can take hours (not part of the rollback)"
    elif [ -z "$PM" ]; then
        pkgline="unrecognised distro: listed for you to install"
    else
        pkgline="$PM via $SUDO, core packages"
        if declare -p "COPR_${FAMILY}" >/dev/null 2>&1; then
            local -n _copr="COPR_${FAMILY}"
            pkgline="$pkgline; enables third-party COPR repos: ${_copr[*]}"
        fi
        if [ "$FULL" = "1" ]; then
            pkgline="$pkgline plus the daily apps"
            if declare -p "COPR_${FAMILY}_full" >/dev/null 2>&1; then
                local -n _copr_full="COPR_${FAMILY}_full"
                pkgline="$pkgline (and COPR ${_copr_full[*]} for yazi)"
            fi
        fi
        pkgline="$pkgline (not part of the rollback)"
    fi
    if [ "$KEEP_MONITORS" = "1" ]; then monline="the repo's layout, unchanged"; else monline="portable default, original kept as monitors.lua.example"; fi
    if [ "$WANT_RISHOT" = "1" ]; then rishotline="yes, runs its installer"; else rishotline="no"; fi

    if [ "$SHELL_CHOICE" = "keep" ]; then
        shellline="keep $(current_shell); the hook-up steps for it are printed at the end"
    else
        shellline="$SHELL_CHOICE; you switch to it yourself, the steps are printed at the end"
    fi
    case "$WANT_SIOYEK" in
        0)    sioyekline="no" ;;
        auto) sioyekline="yes, $SIOYEK_ID as a user Flatpak (skipped if flatpak is missing)" ;;
        *)    sioyekline="yes, $SIOYEK_ID as a user Flatpak" ;;
    esac
    if [ "$WANT_RETROARCH" = "1" ]; then retroline="yes, $RETROARCH_ID as a user Flatpak"; else retroline="no"; fi
    if [ "$WANT_GRUB_THEME" = "1" ] && ! grub_present; then
        grubline="requested, but GRUB 2 was not found here, so it will be skipped"
    elif [ "$WANT_GRUB_THEME" = "1" ]; then
        grubline="yes, SEELE ($GRUB_PROFILE), release $EVA_REF, cloned into ~/Projects/Evangelion; edits GRUB config"
    else
        grubline="no"
    fi

    say ""
    say "${BOLD}Plan${RESET}"
    note "source     $SRC_DIR"
    note "configs    ${#CONFIG_ENTRIES[@]} entries into $CONFIG_DIR, merged in: nothing is deleted"
    note "packages   $pkgline"
    note "monitors   $monline"
    note "shell      $shellline"
    note "sioyek     $sioyekline"
    note "retroarch  $retroline"
    note "grub theme $grubline"
    note "rishot     $rishotline"
    note "safety     every path is saved to $BACKUP_DIR before it changes;"
    note "           if the deploy fails, all of it is undone"

    if [ "$DRY_RUN" = "1" ]; then
        STAGE_DETAIL="dry run: nothing is asked"
        return "$ST_OK"
    fi
    if [ "$ASSUME_YES" = "1" ]; then
        STAGE_DETAIL="--yes"
        return "$ST_OK"
    fi

    say ""
    confirm "Continue?" || rc=$?
    case "$rc" in
        0) STAGE_DETAIL="confirmed"; return "$ST_OK" ;;
        1) return "$ST_ABORT" ;;
        *) err "no terminal to ask on. Re-run with --yes once you have read the plan above."
           return "$ST_FAIL" ;;
    esac
}
