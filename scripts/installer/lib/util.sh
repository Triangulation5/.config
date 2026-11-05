# shellcheck shell=bash
# lib/util.sh: small helpers with no opinions.

# has_item NEEDLE ITEM...   plain-array membership. A loop, not a pipeline, so
# SIGPIPE cannot get involved.
has_item() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# Escape a string for the replacement half of sed 's|...|...|'.
sed_escape_replacement() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

# Temporary paths are registered so one place (temp_cleanup, called from the
# EXIT trap) removes them, whichever way the run ends.
TEMP_PATHS=()
temp_register() { TEMP_PATHS+=("$1"); }
temp_cleanup() {
    local p
    for p in "${TEMP_PATHS[@]}"; do
        if [ -n "$p" ]; then rm -rf -- "$p"; fi
    done
    TEMP_PATHS=()
    return 0
}
