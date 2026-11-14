#!/usr/bin/env bash
set -euo pipefail

DIRS=(
    "$HOME/Documents/books"
    "$HOME/Downloads/"
)

# Determine PDF reader: fallback to xdg-open if sioyek is not installed
if command -v sioyek >/dev/null 2>&1; then
    READER="sioyek"
elif command -v zathura >/dev/null 2>&1; then
    READER="zathura"
elif command -v mupdf >/dev/null 2>&1; then
    READER="mupdf"
else
    READER="xdg-open"
fi

shell_join() {
    local arg
    for arg in "$@"; do
        printf '%q ' "$arg"
    done
}

ensure_runner_session() {
    local session="$1" runner_shell="${SHELL:-}"

    if tmux has-session -t "$session" 2>/dev/null; then
        return 0
    fi

    if [[ ! -x "$runner_shell" ]]; then
        runner_shell="$(command -v zsh || command -v bash || command -v sh)"
    fi
    tmux new-session -d -s "$session" -c "$HOME" -n home "$runner_shell"
}

run_in_runner_session() {
    local session="$1"
    local window_name="$2"
    local command="$3"

    ensure_runner_session "$session"
    tmux new-window -d -t "$session:" -c "$HOME" -n "$window_name" "$command"
}

list_documents() {
    {
        fd . "${DIRS[@]}" \
            --max-depth=2 \
            --extension="djvu" \
            --extension="epub" \
            --extension="pdf" \
            --full-path \
            --base-directory "$HOME"

        fd . "$PWD" \
            --type=file \
            --extension="pdf" \
            --hidden \
            --no-ignore \
            --absolute-path
    } | sort -uf \
        | while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            printf '%s\t%s\n' "${path##*/}" "$path"
        done
}

focus_sioyek() {
    local class_name="sioyek"
    local workspace="SIOYEK"

    command -v hyprctl >/dev/null 2>&1 || return 0

    for _ in {1..20}; do
        # Check if a window with class 'sioyek' exists
        if hyprctl clients -j | jq -e --arg cls "$class_name" '.[] | select(.class == $cls)' >/dev/null 2>&1; then
            # Switch to the SIOYEK workspace and focus the client
            hyprctl dispatch workspace "$workspace" >/dev/null 2>&1 || true
            hyprctl dispatch focuswindow "class:$class_name" >/dev/null 2>&1 || true
            return 0
        fi

        sleep 0.15
    done
}

if [[ $# -eq 1 ]]; then
    selected=$1
else
    selected_row="$(
        list_documents \
            | fzf \
                --delimiter=$'\t' \
                --with-nth 1 \
                --nth 1
    )"

    [[ -n "$selected_row" ]] || exit 0
    IFS=$'\t' read -r _display_name selected <<< "$selected_row"
fi

[[ -n "$selected" ]] || exit 0

if [[ -n "${TMUX:-}" ]]; then
    runner_session="${TMUX_RUNNER_SESSION:-background}"
    run_in_runner_session "$runner_session" "pdf" "exec $(shell_join "$READER" "$selected") >/dev/null 2>&1"
    if [[ "$READER" == "sioyek" ]]; then
        focus_sioyek
    fi
    tmux display-message "Opened PDF in tmux session: $runner_session"
    exit 0
fi

"$READER" "$selected" >/dev/null 2>&1 &
pid="$!"
if [[ "$READER" == "sioyek" ]]; then
    focus_sioyek
fi
wait "$pid" 2>/dev/null || true
