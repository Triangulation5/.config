# shellcheck shell=bash
# stages/preflight.sh: can this run at all, and what machine is it on.

stage_preflight() {
    local tool last
    local -a missing=()

    if [ "$(id -u)" -eq 0 ]; then
        err "run this as your normal user, not root: the configs would end up owned by root"
        return "$ST_FAIL"
    fi
    if [ -z "${HOME:-}" ]; then
        err "HOME is not set"
        return "$ST_FAIL"
    fi
    for tool in cp mv rm mkdir find diff sed grep mktemp date chmod; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        err "missing tools the installer itself needs: ${missing[*]}"
        return "$ST_FAIL"
    fi
    if [ -e "$CONFIG_DIR" ] && [ ! -w "$CONFIG_DIR" ]; then
        err "$CONFIG_DIR is not writable by you"
        return "$ST_FAIL"
    fi

    STAGE_DETAIL="bash $BASH_VERSION, uid $(id -u)"

    # A run that died without finishing leaves a journal with no COMMIT and no
    # ROLLED_BACK. Say so, because ~/.config may be half-changed.
    if [ "$MODE" = "install" ]; then
        last="$(txn_latest "$STATE_DIR/backups")"
        if [ -n "$last" ] && [ "$(txn_state "$last/journal")" = "incomplete" ]; then
            warn "an earlier install did not finish: $(basename -- "$last")"
            note "inspect or undo it with: install.sh --rollback $(basename -- "$last")"
            STAGE_DETAIL="earlier install unfinished"
            return "$ST_WARN"
        fi
    fi
    return "$ST_OK"
}

stage_detect() {
    local rc="$ST_OK"
    detect_distro
    if [ "$NO_DEPS" != "1" ]; then
        detect_privilege || return "$ST_FAIL"
        check_distro_repos || rc="$ST_WARN"
    fi
    STAGE_DETAIL="${FAMILY}${PM:+, via $PM}"
    return "$rc"
}
