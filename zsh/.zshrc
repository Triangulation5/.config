# .zshrc

autoload -U colors && colors
# PS1="%B%{$fg[red]%}[%{$fg[yellow]%}%n%{$fg[green]%}@%{$fg[blue]%}%M %{$fg[magenta]%}%~%{$fg[red]%}]%{$reset_color%}$%b "
PS1="%{$fg[magenta]%}%~%{$fg[red]%} %{$reset_color%}$%b "

setopt autocd
stty stop undef
setopt interactive_comments

HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history"
HISTSIZE=100000
SAVEHIST=100000

# History settings
setopt append_history
setopt inc_append_history
setopt share_history
setopt hist_ignore_dups
setopt hist_ignore_all_dups
setopt hist_save_no_dups

setopt autocd nomatch notify
unsetopt beep
bindkey -v

autoload -Uz compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

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
export WWW_HOME="https://lite.duckduckgo.com/lite"

alias v='nvim'
alias vi='vim'
alias crawl='wget --recursive --page-requisites --adjust-extension --convert-links'
alias cc="gcc -Wall -Wextra -std=c23 -pedantic "

export PATH="$HOME/.local/bin:$PATH"

bindkey -s '^F' 'cd "$(dirname "$(fzf)")"\n'
bindkey -s $'\e\C-f' '~/.config/scripts/tmux-session-dispensary.sh\n'
bindkey -s $'\e\C-p' '~/.config/scripts/open-pdf.sh\n'

# Pi
export PATH="/home/josh/.pi/agent/bin:$PATH"
# Added by Antigravity CLI installer
export PATH="/home/josh/.local/bin:$PATH"

# Load the plugin last
source ~/.config/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
