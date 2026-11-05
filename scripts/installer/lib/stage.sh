# shellcheck shell=bash
# lib/stage.sh: the stage contract, the runner, and the exit path.
#
# A stage is a function that does one thing and says how it went:
#
#     stage_example() {
#         STAGE_DETAIL="3 files"          # optional, shown dimmed after the title
#         return "$ST_OK"
#     }
#
# Return one of:
#     ST_OK     0  it did what it says
#     ST_FAIL   1  it could not
#     ST_SKIP   2  nothing to do, or you asked it not to
#     ST_WARN   3  it worked, but something needs attention
#     ST_ABORT  4  the user declined; stop cleanly
#
# Rules a stage follows:
#   * `set -e` is NOT in force inside a stage (it is called from a `||`, which
#     turns errexit off). Check every command that can fail and return ST_FAIL.
#   * End with an explicit `return`. The status of the last command is not a
#     stage status.
#   * Print the reason for a failure with `err` before returning ST_FAIL.
#   * Expected failures return ST_FAIL. `die` is only for bad invocations.
#
# Run a stage with:   stage <required|optional> "Title" stage_fn
#
#   required  failure ends the install. If the config transaction is open it is
#             rolled back first. On a terminal you are offered a retry first.
#   optional  failure is reported and the install goes on. On a terminal you
#             are offered a retry; the final exit status becomes 3.
#
# Exit status of the whole run:
#   0  every stage ok, skipped or warned
#   1  stopped: a required stage failed or you said no (config rolled back)
#   2  bad invocation, nothing ran
#   3  finished, but an optional stage failed

ST_OK=0; ST_FAIL=1; ST_SKIP=2; ST_WARN=3; ST_ABORT=4

STAGE_DETAIL=""
N_OK=0; N_WARN=0; N_SKIP=0; N_FAIL=0
NONFATAL_FAILURES=0
ROLLED_BACK_NOW=0
ROLLBACK_FAILED=0
TXN_WAS_ACTIVE=0
# Set by any stage that changed the machine outside the config transaction
# (packages, third-party installers), so an abort can say what it did NOT undo.
OUTSIDE_TXN_CHANGES=0

summary() {
    printf '\n%s%d ok, %d warn, %d skipped, %d failed%s\n' \
        "$BOLD" "$N_OK" "$N_WARN" "$N_SKIP" "$N_FAIL" "$RESET"
}

# Undo the open transaction, loudly. Safe to call when none is open.
rollback_now() {
    [ "${TXN_ACTIVE:-0}" = "1" ] || return 0
    TXN_WAS_ACTIVE=1
    trap '' INT TERM            # an undo should not be interruptible
    printf '\n'
    note "undoing the config changes made so far"
    if txn_rollback; then
        ROLLED_BACK_NOW=1
        ui_status ok "Roll back changes" "$TXN_ROOT is as it was"
    else
        ROLLBACK_FAILED=1
        ui_status fail "Roll back changes" "some paths could not be restored"
        err "your originals are saved in $TXN_DIR/files"
        err "fix the cause, then run: install.sh --rollback $(basename -- "$TXN_DIR")"
    fi
    return 0
}

# Stop the install: roll back, say what state things are in, exit 1.
abort() {
    printf '\n'
    err "$*"
    rollback_now
    summary
    if [ "$ROLLBACK_FAILED" = "1" ]; then
        err "the install stopped and the rollback did not finish: see above"
    elif [ "$ROLLED_BACK_NOW" = "1" ]; then
        note "stopped. The config changes were rolled back."
        if [ "$OUTSIDE_TXN_CHANGES" = "1" ]; then
            note "Packages and tools installed earlier are outside the transaction and were left in place."
        fi
    else
        note "stopped. No config files were changed."
    fi
    exit 1
}

# The user said no. Not an error, but still not a success.
abort_declined() {
    printf '\n'
    summary
    note "aborted at your request. No config files were changed."
    exit 1
}

# stage POLICY TITLE FN
stage() {
    local policy="$1" title="$2" fn="$3" rc kind
    while :; do
        STAGE_DETAIL=""
        DRY_SKIPPED=0
        rc=0
        progress_start "$title in progress..."
        "$fn" || rc=$?
        progress_stop

        case "$rc" in
            0) kind=ok ;;
            2) kind=skip ;;
            3) kind=warn ;;
            4) kind=abort ;;
            *) kind=fail ;;
        esac
        if [ "$rc" -gt 4 ]; then
            STAGE_DETAIL="internal error: $fn returned $rc"
        fi
        if [ "${DRY_RUN:-0}" = "1" ] && [ "$kind" = "ok" ] && [ "$DRY_SKIPPED" = "1" ]; then
            kind=dry
        fi
        ui_status "$kind" "$title" "$STAGE_DETAIL"

        case "$kind" in
            ok|dry) N_OK=$((N_OK + 1));     return 0 ;;
            warn)   N_WARN=$((N_WARN + 1)); return 0 ;;
            skip)   N_SKIP=$((N_SKIP + 1)); return 0 ;;
            abort)  abort_declined ;;
        esac

        # Failed. A person at a terminal gets to choose; everyone else gets
        # the safe default (required: stop and undo; optional: carry on).
        if [ "$policy" = "required" ]; then
            CHOICE=a
            if [ "${DRY_RUN:-0}" != "1" ]; then
                ask_choice "    [r]etry this stage, or [a]bort and roll back? [a]" a r a
            fi
            [ "$CHOICE" = "r" ] && continue
            N_FAIL=$((N_FAIL + 1))
            abort "$title failed"
        else
            CHOICE=c
            if [ "${DRY_RUN:-0}" != "1" ]; then
                ask_choice "    [r]etry this stage, or [c]ontinue without it? [c]" c r c
            fi
            [ "$CHOICE" = "r" ] && continue
            N_FAIL=$((N_FAIL + 1))
            NONFATAL_FAILURES=$((NONFATAL_FAILURES + 1))
            return 0
        fi
    done
}

# The exit path. Whatever ends the run (normal exit, abort, a signal, set -e
# killing the script) comes through here, so an open transaction never
# survives the process: the safety net behind the explicit rollbacks above.
on_exit() {
    local rc=$?
    progress_stop 2>/dev/null || true
    trap - EXIT
    trap '' INT TERM
    if [ "${TXN_ACTIVE:-0}" = "1" ]; then
        printf '\n'
        err "the installer stopped inside the config transaction (status $rc)"
        rollback_now
        summary
        [ "$rc" -eq 0 ] && rc=1
    fi
    temp_cleanup
    exit "$rc"
}

install_traps() {
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}
