# shellcheck shell=bash
# stages/source.sh: find the files to deploy. Sets SRC_DIR.
#
# Order of preference, from least to most surprising-in-a-bad-way:
#   1. --source PATH           you named it
#   2. the checkout this script lives in (what you are looking at is what ships)
#   3. a clone under --dir, updated with a fast-forward-only fetch

stage_source() {
    local rc="$ST_OK"

    if [ -n "$SRC_OVERRIDE" ]; then
        if [ ! -d "$SRC_OVERRIDE" ]; then
            err "--source $SRC_OVERRIDE is not a directory"
            return "$ST_FAIL"
        fi
        SRC_DIR="$(cd -- "$SRC_OVERRIDE" && pwd)" || return "$ST_FAIL"
        [ -f "$SRC_DIR/hypr/hyprland.lua" ] || warn "$SRC_DIR does not look like a Silhouette checkout"
        STAGE_DETAIL="$SRC_DIR"
        return "$ST_OK"
    fi

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/hypr/hyprland.lua" ] && [ -d "$SCRIPT_DIR/quickshell" ]; then
        SRC_DIR="$SCRIPT_DIR"
        STAGE_DETAIL="this checkout: $SRC_DIR"
        return "$ST_OK"
    fi

    # Everything past here clones or pulls, and this runs before the package
    # step, so git cannot be installed for you yet. A Gentoo stage3 is the
    # common case: it ships without git.
    if ! command -v git >/dev/null 2>&1; then
        if [ "$PM" = "emerge" ]; then
            err "git is needed to fetch the repo: $SUDO emerge --ask dev-vcs/git (or pass --source PATH)"
        else
            err "git is needed to fetch the repo; install it, or pass --source PATH"
        fi
        return "$ST_FAIL"
    fi

    if [ "$DRY_RUN" = "1" ] && [ ! -d "$DEFAULT_SRC" ]; then
        # A dry run still needs something to read. Clone into a temp dir that
        # is deleted on exit, so the promise of "changes nothing" holds.
        TMP_SRC="$(mktemp -d)" || return "$ST_FAIL"
        temp_register "$TMP_SRC"
        note "dry run: fetching into a temporary directory"
        if ! git clone --depth 1 --branch "$REF" -- "$REPO_URL" "$TMP_SRC" >/dev/null 2>&1; then
            err "could not clone $REPO_URL ($REF)"
            return "$ST_FAIL"
        fi
        SRC_DIR="$TMP_SRC"
        STAGE_DETAIL="temporary clone of $REF"
        return "$ST_OK"
    fi

    if [ -d "$DEFAULT_SRC/.git" ]; then
        note "updating $DEFAULT_SRC"
        # fetch + fast-forward only: never discards edits in your own clone,
        # and does not half-apply a diverged branch.
        if ! run git -C "$DEFAULT_SRC" fetch --depth 1 origin "$REF"; then
            # A failed fetch is a setback, not a stop: the clone on disk is a
            # complete copy of the repo as of the last time it worked.
            warn "could not fetch $REF; deploying the clone as it is on disk"
            STAGE_DETAIL="fetch failed, using the existing clone"
            rc="$ST_WARN"
        elif [ "$DRY_RUN" != "1" ] \
             && ! git -C "$DEFAULT_SRC" merge --ff-only FETCH_HEAD >/dev/null 2>&1; then
            warn "$DEFAULT_SRC has local changes; deploying what is on disk as-is"
            STAGE_DETAIL="local changes kept"
            rc="$ST_WARN"
        fi
    elif [ -e "$DEFAULT_SRC" ] && [ -n "$(ls -A "$DEFAULT_SRC" 2>/dev/null)" ]; then
        err "$DEFAULT_SRC exists and is not a git checkout. Pass --dir or --source."
        return "$ST_FAIL"
    else
        note "cloning $REPO_URL ($REF) into $DEFAULT_SRC"
        run mkdir -p "$(dirname -- "$DEFAULT_SRC")" || return "$ST_FAIL"
        if ! run git clone --depth 1 --branch "$REF" -- "$REPO_URL" "$DEFAULT_SRC"; then
            err "could not clone $REPO_URL ($REF)"
            return "$ST_FAIL"
        fi
    fi
    SRC_DIR="$DEFAULT_SRC"
    [ -n "$STAGE_DETAIL" ] || STAGE_DETAIL="$SRC_DIR"
    return "$rc"
}
