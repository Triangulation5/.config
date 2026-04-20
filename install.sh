#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "[ERROR] $1" >&2
  exit 1
}

warn() {
  echo "[WARN] $1" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

echo "==> Detecting package manager"

install_packages() {
  if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y git curl fzf ripgrep zoxide neovim bat
  elif command -v brew >/dev/null 2>&1; then
    brew install git curl fzf ripgrep zoxide neovim bat
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git curl fzf ripgrep zoxide neovim bat
  else
    fail "No supported package manager found"
  fi
}

install_packages

echo "==> Verifying core dependencies"

for cmd in git curl fzf rg zoxide nvim bat; do
  require_cmd "$cmd"
done

echo "==> Setting XDG paths (non-destructive)"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

echo "==> Creating config directories"

mkdir -p \
  "$XDG_CONFIG_HOME/nvim" \
  "$XDG_CONFIG_HOME/yazi" \
  "$XDG_CONFIG_HOME/bat" \
  "$XDG_CONFIG_HOME/ripgrep"

link() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    fail "Source missing: $src"
  fi

  local tmp="${dst}.tmp"

  # try symlink first
  if ln -s "$src" "$tmp" 2>/dev/null; then

    if [[ -e "$dst" || -L "$dst" ]]; then
      local backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
      mv "$dst" "$backup"
      echo "Backup created: $backup"
    fi

    mv "$tmp" "$dst"
    echo "Linked: $dst"
    return
  fi

  warn "Symlink failed for $dst, falling back to copy"

  rm -rf "$dst"
  cp -r "$src" "$dst" || fail "Copy failed for $dst"
  echo "Copied: $dst"
}

echo "==> Symlinking dotfiles"

link "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"
link "$DOTFILES_DIR/editors/vim/.vimrc" "$HOME/.vimrc"
link "$DOTFILES_DIR/editors/nvim/init.lua" "$XDG_CONFIG_HOME/nvim/init.lua"
link "$DOTFILES_DIR/tools/yazi" "$XDG_CONFIG_HOME/yazi"

if [[ -d "$DOTFILES_DIR/bat/themes" ]]; then
  mkdir -p "$XDG_CONFIG_HOME/bat/themes"
  link "$DOTFILES_DIR/bat/themes" "$XDG_CONFIG_HOME/bat/themes"
fi

echo "==> Shell integrations"

BASHRC="$HOME/.bashrc"

ensure_line() {
  local file="$1"
  local line="$2"

  [[ -f "$file" ]] || touch "$file"

  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

if [[ -d "$HOME/.fzf" ]]; then
  "$HOME/.fzf/install" --all --no-bash --no-fish || warn "fzf install partially failed"
fi

ensure_line "$BASHRC" 'eval "$(zoxide init bash)"'
ensure_line "$BASHRC" 'export EDITOR=nvim'
ensure_line "$BASHRC" 'export FZF_DEFAULT_OPTS="--layout=reverse --border"'
ensure_line "$BASHRC" 'export BAT_THEME="default"'

echo "==> Validating final state"

for cmd in git curl fzf rg zoxide nvim bat; do
  command -v "$cmd" >/dev/null 2>&1 || warn "Missing after install: $cmd"
done

echo "==> Install complete"
