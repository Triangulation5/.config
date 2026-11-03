# shellcheck shell=bash
# lib/txn.sh: an undo journal for a directory tree.
#
# The guarantee: between txn_begin and txn_commit, every path that is about to
# change is recorded first, so txn_rollback can put the tree back exactly as it
# was. Nothing here knows what Silhouette is; ROOT is just a directory.
#
# Two kinds of record, one per line, tab separated, paths relative to ROOT:
#
#   ROOT    <abs path>   first line; where the journal applies
#   BACKUP  <rel>        <rel> existed. Its content is saved in files/<rel>
#                        BEFORE it is touched. Rollback copies it back.
#   NEW     <rel>        <rel> did not exist. Rollback removes it.
#   COMMIT               last line of a finished install
#   ROLLED_BACK          last line once a rollback has completed
#
# Replay runs in reverse. Directories that were merged into are restored by
# merging the backup back over them, not by deleting and recreating, so a file
# you added after the install is not collateral damage of an undo.
#
# Rules for callers:
#   - Call txn_protect REL *before* modifying REL, and treat a non-zero return
#     as "do not touch it".
#   - For a directory you will merge files into, also call
#     txn_track_new_children, so files you add to it can be removed again.
#   - A journal with neither COMMIT nor ROLLED_BACK means the run died. That is
#     the "incomplete" state; --rollback can still undo it.
#
# Under --dry-run txn_begin is never called, TXN_ACTIVE stays 0, and every
# function below is a no-op.

TXN_ACTIVE=0
TXN_ROOT=""
TXN_DIR=""
TXN_JOURNAL=""
declare -A TXN_SEEN=()      # rel -> B (backed up) | N (new)
declare -A TXN_TRACKED=()   # dirs whose new children were already recorded

_txn_log() {
    printf '%s\t%s\n' "$1" "$2" >> "$TXN_JOURNAL"
}

# txn_begin ROOT DIR   DIR holds the journal and the backups.
txn_begin() {
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    TXN_ROOT="$1"
    TXN_DIR="$2"
    TXN_JOURNAL="$2/journal"
    if [ -e "$TXN_JOURNAL" ]; then
        err "$TXN_JOURNAL already exists; wait a second and run again"
        return 1
    fi
    mkdir -p -- "$TXN_DIR/files" || return 1
    : > "$TXN_JOURNAL" || return 1
    _txn_log ROOT "$TXN_ROOT" || return 1
    TXN_ACTIVE=1
    return 0
}

# Sets TXN_COVER to the record of the nearest ancestor-or-self of $1 that is
# already journaled (B, N or empty).
_txn_cover() {
    local rel="$1" k best=-1
    TXN_COVER=""
    for k in "${!TXN_SEEN[@]}"; do
        if [ "$rel" = "$k" ] || [ "${rel#"$k"/}" != "$rel" ]; then
            if [ "${#k}" -gt "$best" ]; then
                best="${#k}"
                TXN_COVER="${TXN_SEEN[$k]}"
            fi
        fi
    done
}

# txn_protect REL   journal REL's current state. Idempotent: a path that is
# already covered is not backed up a second time, which matters on a retry,
# when the live copy is already half-changed.
txn_protect() {
    local rel="$1" abs
    [ "$TXN_ACTIVE" = "1" ] || return 0
    abs="$TXN_ROOT/$rel"
    _txn_cover "$rel"

    if [ -e "$abs" ] || [ -L "$abs" ]; then
        # Already inside a backed-up directory, or something we created:
        # nothing to save.
        [ -n "$TXN_COVER" ] && return 0
        mkdir -p -- "$(dirname -- "$TXN_DIR/files/$rel")" || return 1
        cp -a -- "$abs" "$TXN_DIR/files/$rel" || return 1
        _txn_log BACKUP "$rel" || return 1
        TXN_SEEN["$rel"]=B
    else
        # A new path is recorded even inside a backed-up directory: the backup
        # was taken without it.
        [ "$TXN_COVER" = "N" ] && return 0
        _txn_log NEW "$rel" || return 1
        TXN_SEEN["$rel"]=N
    fi
    return 0
}

# txn_track_new_children REL SRC   REL is a directory that exists and that SRC
# (a directory) will be merged into. Record every path SRC would add to it.
txn_track_new_children() {
    local rel="$1" src="$2" p
    local -a newdirs=()
    local nd skip
    [ "$TXN_ACTIVE" = "1" ] || return 0
    [ -z "${TXN_TRACKED[$rel]:-}" ] || return 0   # retry: files already exist now
    TXN_TRACKED["$rel"]=1

    while IFS= read -r -d '' p; do
        p="${p#./}"
        if [ -e "$TXN_ROOT/$rel/$p" ] || [ -L "$TXN_ROOT/$rel/$p" ]; then
            continue
        fi
        skip=0
        for nd in "${newdirs[@]}"; do
            if [ "${p#"$nd"/}" != "$p" ]; then skip=1; break; fi
        done
        [ "$skip" = "1" ] && continue
        _txn_log NEW "$rel/$p" || return 1
        TXN_SEEN["$rel/$p"]=N
        if [ -d "$src/$p" ] && [ ! -L "$src/$p" ]; then newdirs+=("$p"); fi
    done < <(cd -- "$src" && find . -mindepth 1 -print0)
    return 0
}

txn_commit() {
    [ "$TXN_ACTIVE" = "1" ] || return 0
    printf 'COMMIT\n' >> "$TXN_JOURNAL" || return 1
    TXN_ACTIVE=0
    return 0
}

_txn_safe_rel() {
    case "$1" in
        ''|/*|..|../*|*/..|*/../*) return 1 ;;
    esac
    return 0
}

_txn_restore() {
    local src="$1" dst="$2"
    if [ -d "$src" ] && [ ! -L "$src" ]; then
        mkdir -p -- "$dst" && cp -af -- "$src/." "$dst/"
    else
        mkdir -p -- "$(dirname -- "$dst")" && cp -af -- "$src" "$dst"
    fi
}

# txn_rollback [JOURNAL]   replay in reverse. Best effort: a path that cannot
# be restored is reported and the rest still are. Returns non-zero if any
# failed, and then does NOT mark the journal rolled back, so it can be retried.
txn_rollback() {
    local journal="${1:-$TXN_JOURNAL}" dir root="" kind rel i bad=0
    local -a kinds=() rels=()
    [ -r "$journal" ] || { err "no journal at $journal"; return 1; }
    dir="$(dirname -- "$journal")"

    while IFS=$'\t' read -r kind rel; do
        case "$kind" in
            ROOT)       root="$rel" ;;
            BACKUP|NEW) kinds+=("$kind"); rels+=("$rel") ;;
        esac
    done < "$journal"
    [ -n "$root" ] || { err "journal has no ROOT line: $journal"; return 1; }

    for ((i = ${#kinds[@]} - 1; i >= 0; i--)); do
        kind="${kinds[i]}"
        rel="${rels[i]}"
        if ! _txn_safe_rel "$rel"; then
            warn "ignoring suspicious path in the journal: $rel"
            bad=1
            continue
        fi
        case "$kind" in
            NEW)
                rm -rf -- "${root:?}/$rel" || { warn "could not remove $rel"; bad=1; }
                ;;
            BACKUP)
                _txn_restore "$dir/files/$rel" "$root/$rel" \
                    || { warn "could not restore $rel"; bad=1; }
                ;;
        esac
    done

    TXN_ACTIVE=0
    if [ "$bad" = "0" ]; then
        printf 'ROLLED_BACK\n' >> "$journal" || return 1
    fi
    return "$bad"
}

# txn_state JOURNAL   prints: committed | rolledback | incomplete
txn_state() {
    if grep -qx 'ROLLED_BACK' "$1" 2>/dev/null; then
        echo rolledback
    elif grep -qx 'COMMIT' "$1" 2>/dev/null; then
        echo committed
    else
        echo incomplete
    fi
}

# txn_latest BACKUPS_DIR   newest directory that holds a journal. Timestamps
# sort lexically, so the glob order is the chronological order.
txn_latest() {
    local d latest=""
    for d in "$1"/*/; do
        [ -f "${d}journal" ] && latest="${d%/}"
    done
    printf '%s' "$latest"
}
