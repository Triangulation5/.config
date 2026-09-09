# .zshrc

autoload -U colors && colors
PS1="%B%{$fg[red]%}[%{$fg[yellow]%}%n%{$fg[green]%}@%{$fg[blue]%}%M %{$fg[magenta]%}%~%{$fg[red]%}]%{$reset_color%}$%b "
# PS1="%{$fg[magenta]%}%~%{$fg[red]%} %{$reset_color%}$%b "

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

alias v='nvim'
alias vi='vim'

alias fingerprint="bash ~/.config/hypr/scripts/fingerprint.sh" # Run fingerprint script

export PATH="$HOME/.local/bin:$PATH"

bindkey -s '^f' '^ucd "$(dirname "$(fzf)")"\n'

# Load the plugin last
source ~/.config/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
