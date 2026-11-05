# shellcheck shell=bash
# stages/rollback.sh: `install.sh --rollback [STAMP]`. Replays an install's
# journal in reverse. Works on a finished install and on one that died halfway.

stage_rollback() {
    local root="$STATE_DIR/backups" dir state nb nn rc=0

    if [ -n "$ROLLBACK_STAMP" ]; then
        dir="$root/$ROLLBACK_STAMP"
    else
        dir="$(txn_latest "$root")"
    fi
    if [ -z "$dir" ] || [ ! -r "$dir/journal" ]; then
        err "no install to roll back in $root"
        return "$ST_FAIL"
    fi

    state="$(txn_state "$dir/journal")"
    if [ "$state" = "rolledback" ]; then
        STAGE_DETAIL="$(basename -- "$dir") was already rolled back"
        return "$ST_SKIP"
    fi

    nb="$(grep -c "^BACKUP$(printf '\t')" "$dir/journal" || true)"
    nn="$(grep -c "^NEW$(printf '\t')" "$dir/journal" || true)"
    note "install:  $(basename -- "$dir") ($state)"
    note "restores: $nb path(s) saved before the install changed them"
    note "removes:  $nn path(s) the install created"

    if [ "$DRY_RUN" = "1" ]; then
        would_do rollback "$dir/journal"
        return "$ST_OK"
    fi

    confirm "    Roll this install back?" || rc=$?
    case "$rc" in
        0) ;;
        1) return "$ST_ABORT" ;;
        *) err "no terminal to ask on. Re-run with --yes to roll back without asking."
           return "$ST_FAIL" ;;
    esac

    txn_rollback "$dir/journal" || { err "rollback did not finish"; return "$ST_FAIL"; }
    STAGE_DETAIL="$(basename -- "$dir") undone"
    return "$ST_OK"
}
