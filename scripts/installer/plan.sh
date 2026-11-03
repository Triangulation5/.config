# shellcheck shell=bash
# stages/plan.sh: interview, then plan, then one confirmation.
#
# Everything the user gets a say in is asked here, before anything changes, so
# the plan that is confirmed is the plan that runs. Answers land in FULL,
# KEEP_MONITORS and WANT_RISHOT. A flag already answered a question; with no
# terminal (or --yes) a question takes its default.

stage_plan() {
    local rc=0 pkgline monline rishotline

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

    if [ "$NO_DEPS" = "1" ]; then
        pkgline="skipped (--no-deps)"
    elif [ "$PM" = "emerge" ]; then
        pkgline="checked, then printed as an emerge command for you to run"
    elif [ -z "$PM" ]; then
        pkgline="unrecognised distro: listed for you to install"
    else
        pkgline="$PM via $SUDO, core packages"
        if declare -p "COPR_${FAMILY}" >/dev/null 2>&1; then
            local -n _copr="COPR_${FAMILY}"
            pkgline="$pkgline; enables third-party COPR repos: ${_copr[*]}"
        fi
        [ "$FULL" = "1" ] && pkgline="$pkgline plus the daily apps"
        pkgline="$pkgline (not part of the rollback)"
    fi
    if [ "$KEEP_MONITORS" = "1" ]; then monline="the repo's layout, unchanged"; else monline="portable default, original kept as monitors.lua.example"; fi
    if [ "$WANT_RISHOT" = "1" ]; then rishotline="yes, runs its installer"; else rishotline="no"; fi

    say ""
    say "${BOLD}Plan${RESET}"
    note "source     $SRC_DIR"
    note "configs    ${#CONFIG_ENTRIES[@]} entries into $CONFIG_DIR, merged in: nothing is deleted"
    note "packages   $pkgline"
    note "monitors   $monline"
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
