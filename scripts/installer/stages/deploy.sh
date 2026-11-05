# shellcheck shell=bash
# stages/deploy.sh: everything that writes into ~/.config.
#
# These stages run between stage_txn_begin and stage_txn_commit. Every path
# they change goes through txn_protect first, so if any required stage fails the
# whole set is undone, not just the one that failed.

stage_txn_begin() {
    if [ "$DRY_RUN" = "1" ]; then
        would_do journal "$BACKUP_DIR/journal"
        STAGE_DETAIL="journal would go to $BACKUP_DIR"
        return "$ST_OK"
    fi
    if ! txn_begin "$CONFIG_DIR" "$BACKUP_DIR"; then
        err "could not create $BACKUP_DIR"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="journal in $BACKUP_DIR"
    return "$ST_OK"
}

stage_txn_commit() {
    if [ "$DRY_RUN" = "1" ]; then
        STAGE_DETAIL="nothing to commit"
        return "$ST_OK"
    fi
    if ! txn_commit; then
        err "could not write the commit record"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="the changes are final; undo with --rollback $STAMP"
    return "$ST_OK"
}

# Journal, then merge in. `cp -a src/. dst/` (rather than replacing the
# directory) keeps files that exist only on the target, which is the difference
# between an install and a wipe. Returns non-zero if the entry did not land.
deploy_entry() {
    local entry="$1"
    local src="$SRC_DIR/$entry" dst="$CONFIG_DIR/$entry"

    [ -e "$src" ] || return 0

    # Running the installer from a checkout that is already ~/.config (the
    # most likely way to run it on this machine) makes every source equal to
    # its target. Copying a path onto itself fails, so say so and move on.
    if [ "$src" = "$dst" ]; then
        dim "source is the target: ~/.config/$entry"
        return 0
    fi

    if [ -e "$dst" ]; then
        if { [ -d "$src" ] && diff -rq -- "$src" "$dst" >/dev/null 2>&1; } \
           || { [ -f "$src" ] && [ -f "$dst" ] && cmp -s -- "$src" "$dst"; }; then
            dim "already up to date: ~/.config/$entry"
            return 0
        fi
        note "backing up ~/.config/$entry"
    fi

    # Nothing below may touch dst until its old state is on record.
    if ! txn_protect "$entry"; then
        err "could not save ~/.config/$entry before changing it; left untouched"
        return 1
    fi
    if [ -d "$src" ] && [ -e "$dst" ]; then
        txn_track_new_children "$entry" "$src" || {
            err "could not journal the new files for ~/.config/$entry; left untouched"
            return 1
        }
    fi

    # -f because some vendored files arrive read-only (a 444 flavour or plugin
    # file cannot be opened for writing, but it can be unlinked and rewritten).
    # Without it, a second install fails on the files the first one deployed.
    if [ -d "$src" ]; then
        run mkdir -p "$dst" || return 1
        if ! run cp -af -- "$src/." "$dst/"; then
            warn "could not copy all of ~/.config/$entry (see the errors above)"
            return 1
        fi
    else
        # A single file is replaced by rename, never rewritten in place: one of
        # them is install.sh, which may be the script that is running right now.
        # A rename leaves the running copy's inode untouched.
        if ! run cp -af -- "$src" "$dst.new.$$" || ! run mv -f -- "$dst.new.$$" "$dst"; then
            [ "$DRY_RUN" = "1" ] || rm -f -- "$dst.new.$$"
            warn "could not copy ~/.config/$entry"
            return 1
        fi
    fi
    note "deploying ~/.config/$entry"
    return 0
}

stage_deploy_configs() {
    local entry i=0 total="${#CONFIG_ENTRIES[@]}"
    FAILED_ENTRIES=()
    if ! run mkdir -p "$CONFIG_DIR"; then
        err "could not create $CONFIG_DIR"
        return "$ST_FAIL"
    fi
    for entry in "${CONFIG_ENTRIES[@]}"; do
        i=$((i + 1))
        progress_bar "$i" "$total" "deploying ~/.config/$entry"
        deploy_entry "$entry" || FAILED_ENTRIES+=("$entry")
    done
    progress_stop

    if [ "${#FAILED_ENTRIES[@]}" -gt 0 ]; then
        err "did not copy cleanly: ${FAILED_ENTRIES[*]}"
        note "This is usually ownership or permissions, not the configs."
        STAGE_DETAIL="${#FAILED_ENTRIES[@]} of ${#CONFIG_ENTRIES[@]} entries failed"
        return "$ST_FAIL"
    fi
    STAGE_DETAIL="${#CONFIG_ENTRIES[@]} entries"
    return "$ST_OK"
}

# Where a later stage should look for REL. After a real deploy that is the
# live copy. In a dry run nothing was deployed, so it is the repo's copy: the
# file the real run would have put there.
live_path() {
    local rel="$1"
    if [ "$DRY_RUN" = "1" ] && [ ! -e "$CONFIG_DIR/$rel" ] && [ -e "$SRC_DIR/$rel" ]; then
        printf '%s' "$SRC_DIR/$rel"
    else
        printf '%s' "$CONFIG_DIR/$rel"
    fi
}

# Rewrite the author's home to yours. Each file is journaled first: when the
# entry was already up to date it has no backup yet.
stage_home_paths() {
    local rel f esc n=0 bad=0

    if [ "$HOME" = "/home/josh" ]; then
        STAGE_DETAIL="already /home/josh"
        return "$ST_SKIP"
    fi
    esc="$(sed_escape_replacement "$HOME")"

    for rel in "${HOME_REWRITE[@]}"; do
        f="$(live_path "$rel")"
        [ -f "$f" ] || continue
        grep -q '/home/josh' "$f" 2>/dev/null || continue
        if [ "$DRY_RUN" = "1" ]; then
            would_do rewrite "/home/josh to $HOME in $rel"
            n=$((n + 1))
            continue
        fi
        if ! txn_protect "$rel"; then
            err "could not save $rel before rewriting it"
            bad=1
            continue
        fi
        if sed -i "s|/home/josh|$esc|g" "$f"; then
            note "rewrote hardcoded paths in $rel"
            n=$((n + 1))
        else
            err "could not rewrite $rel"
            bad=1
        fi
    done

    [ "$bad" = "0" ] || return "$ST_FAIL"
    if [ "$n" -eq 0 ]; then
        STAGE_DETAIL="nothing to rewrite"
        return "$ST_SKIP"
    fi
    STAGE_DETAIL="$n file(s)"
    return "$ST_OK"
}

# A few files in scripts are not executable in the repo (a helper meant to be
# run by hand, and python engines the shell invokes as `python3 <file>`). Make
# the lot executable anyway: Hyprland's binds exec these by path, and a
# non-executable one is a bind that silently does nothing.
stage_script_modes() {
    local dir f rel n=0 bad=0
    dir="$(live_path scripts)"

    if [ ! -d "$dir" ]; then
        STAGE_DETAIL="no scripts directory"
        return "$ST_SKIP"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        would_do run "chmod +x $dir/*.sh $dir/*.py"
        return "$ST_OK"
    fi
    for f in "$dir"/*.sh "$dir"/*.py; do
        [ -f "$f" ] || continue
        [ -x "$f" ] && continue
        rel="scripts/$(basename -- "$f")"
        if ! txn_protect "$rel"; then
            err "could not save $rel before changing its mode"
            bad=1
            continue
        fi
        if chmod +x -- "$f"; then
            n=$((n + 1))
        else
            err "could not make $rel executable"
            bad=1
        fi
    done
    [ "$bad" = "0" ] || return "$ST_FAIL"
    STAGE_DETAIL="$n script(s) made executable"
    return "$ST_OK"
}

write_portable_monitors() {
    cat > "$1" <<'LUA'
-- Written by install.sh: one monitor at its preferred mode, no hardcoded model
-- or scale, so the session comes up on whatever it is attached to.
-- The layout this repo shipped with is next to this file, as
-- monitors.lua.example. Swap it back in from Settings or by hand.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "", persistent = true })
end
LUA
}

# Set once the example copy exists, so a retry after a failed write does not
# mistake our own copy for "the user already has one".
MONITORS_EXAMPLE_MADE=0

stage_monitors() {
    local rel="hypr/modules/monitors.lua"
    local dst="$CONFIG_DIR/$rel" example="$CONFIG_DIR/$rel.example" tmp
    [ "$DRY_RUN" = "1" ] && dst="$(live_path "$rel")"

    if [ "$KEEP_MONITORS" = "1" ]; then
        STAGE_DETAIL="kept the repo's layout"
        return "$ST_SKIP"
    fi
    if [ ! -f "$dst" ]; then
        STAGE_DETAIL="no monitors.lua deployed"
        return "$ST_SKIP"
    fi
    if [ -e "$example" ] && [ "$MONITORS_EXAMPLE_MADE" != "1" ]; then
        dim "monitors.lua.example exists, leaving your layout alone"
        STAGE_DETAIL="your layout was left alone"
        return "$ST_SKIP"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        would_do copy "monitors.lua to monitors.lua.example"
        would_do write "the portable default to ~/.config/$rel"
        return "$ST_OK"
    fi

    # NEW for the example, BACKUP for the layout we are about to replace.
    txn_protect "$rel.example" || { err "could not journal monitors.lua.example"; return "$ST_FAIL"; }
    txn_protect "$rel"         || { err "could not save monitors.lua"; return "$ST_FAIL"; }

    if [ "$MONITORS_EXAMPLE_MADE" != "1" ]; then
        cp -a -- "$dst" "$example" || { err "could not write monitors.lua.example"; return "$ST_FAIL"; }
        MONITORS_EXAMPLE_MADE=1
    fi
    tmp="$dst.tmp.$$"
    if write_portable_monitors "$tmp" && mv -f -- "$tmp" "$dst"; then
        note "monitor layout: portable default written, original kept as monitors.lua.example"
        STAGE_DETAIL="portable default; original kept as monitors.lua.example"
        return "$ST_OK"
    fi
    rm -f -- "$tmp"
    err "could not write the portable monitor layout"
    return "$ST_FAIL"
}
