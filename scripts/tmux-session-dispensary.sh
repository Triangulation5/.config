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

    selected=$(
        fd --type d --max-depth 1 . "${DIRS[@]}" 2>/dev/null |
            sort -u |
            fzf \
                --height=100% \
                --layout=reverse \
                --info=hidden \
                --prompt='tmux session > ' \
                --scheme=path
    ) || exit 0
fi

# Exit if the picker was cancelled or no directory was selected.
[[ -n "$selected" ]] || exit 0

# Expand a leading ~ and normalize to an absolute path.
if [[ "$selected" == "~" ]]; then
    selected=$HOME
elif [[ "$selected" == "~/"* ]]; then
    selected="$HOME/${selected#~/}"
elif [[ "$selected" != /* ]]; then
    selected="$PWD/$selected"
fi

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
        tr -cd '[:alnum:]_-'
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
    tmux new-session -d \
        -s "$selected_name" \
        -c "$selected" \
        zsh
fi

# Switch clients inside tmux; otherwise attach to the session.
if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "=$selected_name"
else
    exec tmux attach-session -t "=$selected_name"
fi
