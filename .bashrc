# .bashrc

# Colors
force_color_prompt=yes
PS1="\[\e[1m\]\[\e[31m\][\[\e[33m\]\u\[\e[38;2;96;96;121m\]@\[\e[34m\]\h \[\e[35m\]\w\[\e[31m\]]\[\e[0m\]\$ "

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# History
HISTSIZE=100
HISTFILESIZE=100
HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/bash/history"
mkdir -p "$(dirname "$HISTFILE")"
shopt -s histappend
PROMPT_COMMAND="history -a; history -n"

# Completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
  source /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
  source /etc/bash_completion
fi

bind 'set match-hidden-files on'

# Vim mode
# set -o vi
# bind -m vi-insert '"\C-l": clear-screen'

# Automatically cd into directory names
shopt -s autocd 2>/dev/null

# Cursor shape switching
function __set_cursor_block { echo -ne '\e[1 q'; }
function __set_cursor_beam  { echo -ne '\e[5 q'; }

PROMPT_COMMAND="__set_cursor_beam; history -a; history -n"

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}

export EDITOR=nvim
export VISUAL=nvim
export MANPAGER='nvim +Man!'
alias v='nvim'

export PATH="$HOME/.cargo/bin:$PATH"
. "$HOME/.cargo/env"

bind -x '"\C-f": cd "$(dirname "$(fzf)")"'
