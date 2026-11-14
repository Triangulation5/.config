#!/usr/bin/env bash
#
# The tmux helpers must not assume zsh exists when the user's selected shell is
# unavailable.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/project"
cat > "$tmp/bin/tmux" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_LOG"
case "$1" in
    has-session) exit 1 ;;
    *) exit 0 ;;
esac
SH
cat > "$tmp/bin/sioyek" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$tmp/bin/tmux" "$tmp/bin/sioyek"

expected="$(command -v zsh || command -v bash || command -v sh)"
export PATH="$tmp/bin:$PATH"
export SHELL="$tmp/not-installed"
export TMUX=mock
export TMUX_LOG="$tmp/tmux.log"

bash "$here/tmux-session-dispensary.sh" "$tmp/project"
grep -F -- "$expected" "$TMUX_LOG"

: > "$TMUX_LOG"
bash "$here/open-pdf.sh" "$tmp/book.pdf"
grep -F -- "$expected" "$TMUX_LOG"

printf '%s\n' ok
