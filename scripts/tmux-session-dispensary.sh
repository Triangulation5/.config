#!/usr/bin/env bash
set -euo pipefail

# Directories to search for tmux sessions.
DIRS=(
    "$HOME"
    "$HOME/Projects"
    "$HOME/Documents"
    "$HOME/Downloads"
)

# Resolve and validate the selected directory.
if [[ $# -ge 1 ]]; then
    selected=$1
else
    command -v fzf >/dev/null 2>&1 || {
        printf 'Error: fzf is not installed.\n' >&2
        exit 1
    }

    command -v fd >/dev/null 2>&1 || {
        printf 'Error: fd is not installed.\n' >&2
        exit 1
    }

    fzf_status=0
    fzf_output=$(
        fd --type d --max-depth 1 . "${DIRS[@]}" 2>/dev/null |
            sort -u |
            fzf \
                --print-query \
                --height=100% \
                --layout=reverse \
                --info=hidden \
                --prompt='tmux session > ' \
                --scheme=path
    ) || fzf_status=$?

    case "$fzf_status" in
        0)
            mapfile -t fzf_lines <<< "$fzf_output"
            selected="${fzf_lines[1]:-}"
            ;;
        1)
            mapfile -t fzf_lines <<< "$fzf_output"
            selected="${fzf_lines[0]:-}"
            ;;
        130)
            exit 0
            ;;
        *)
            exit "$fzf_status"
            ;;
    esac
fi

# Exit if the picker was cancelled or no directory was selected.
[[ -n "$selected" ]] || exit 0

# Safely expand $VAR and ${VAR} references without eval.
expand_env_vars() {
    local input=$1
    local result=""
    local var_name

    while [[ "$input" =~ ^([^$]*)(\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*))(.*)$ ]]; do
        result+="${BASH_REMATCH[1]}"
        var_name="${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}"
        if [[ -v "$var_name" ]]; then
            result+="${!var_name}"
        else
            result+="${BASH_REMATCH[2]}"
        fi
        input="${BASH_REMATCH[5]}"
    done

    printf '%s%s\n' "$result" "$input"
}

selected=$(expand_env_vars "$selected")

# Expand a leading ~ and normalize to an absolute path.
case "$selected" in
    "~")
        selected=$HOME
        ;;
    "~/"*)
        selected="$HOME/${selected#"~/"}"
        ;;
    /*)
        ;;
    *)
        selected="$PWD/$selected"
        ;;
esac

# Ensure the selected path is a directory.
if [[ ! -d "$selected" ]]; then
    printf 'Error: not a directory: %s\n' "$selected" >&2
    exit 1
fi

# Resolve symlinks and obtain the physical absolute path.
selected=$(cd "$selected" && pwd -P)

# Build a valid tmux session name from the full directory path.
# Using the full path avoids collisions between directories with
# identical basenames in different locations.
selected_name=$(
    printf '%s' "$selected" |
        sed "s|^$HOME|~|" |
        tr '/.:' '___' |
        tr -cd '[:alnum:]_-' |
        tr -s '_'
)

# Ensure the session name is not empty.
if [[ -z "$selected_name" ]]; then
    printf 'Error: could not generate a session name for: %s\n' "$selected" >&2
    exit 1
fi

# Create the session only if it does not already exist.
# Leave the initial window unnamed so tmux can automatically
# rename it based on the foreground command.
if ! tmux has-session -t "=$selected_name" 2>/dev/null; then
    runner_shell="${SHELL:-}"
    if [[ ! -x "$runner_shell" ]]; then
        runner_shell="$(command -v zsh || command -v bash || command -v sh)"
    fi
    tmux new-session -d \
        -s "$selected_name" \
        -c "$selected" \
        "$runner_shell"
fi

# Switch clients inside tmux; otherwise attach to the session.
if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "=$selected_name"
else
    exec tmux attach-session -t "=$selected_name"
fi
