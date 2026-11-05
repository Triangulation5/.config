# shellcheck shell=bash
# stages/shell.sh: which shell, and the manual steps to switch to it.
#
# Changing a login shell needs your password and affects every future login, so
# the installer never does it. It installs the shell you picked (bash or zsh),
# or leaves yours alone (keep), and prints the exact commands to finish by hand.

# The login shell recorded for this user, which is what chsh changes, as a bare
# name. $SHELL is only a fallback: the environment can disagree with passwd.
current_shell() {
    local s=""
    if command -v getent >/dev/null 2>&1; then
        s="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
    fi
    [ -n "$s" ] || s="${SHELL:-}"
    if [ -z "$s" ]; then
        printf 'unknown'
        return 0
    fi
    basename -- "$s"
}

# The shell whose config should be wired up: the one picked, or when keeping,
# the current one if it is bash or zsh (nothing else has a config here).
target_shell() {
    case "$SHELL_CHOICE" in
        bash|zsh) printf '%s' "$SHELL_CHOICE" ;;
        *) case "$(current_shell)" in
               bash) printf 'bash' ;;
               zsh)  printf 'zsh' ;;
           esac ;;
    esac
}

stage_shell() {
    local cur target bin
    cur="$(current_shell)"

    if [ "$SHELL_CHOICE" != "bash" ] && [ "$SHELL_CHOICE" != "zsh" ]; then
        STAGE_DETAIL="keeping $cur"
        return "$ST_SKIP"
    fi
    target="$SHELL_CHOICE"

    if [ "$DRY_RUN" = "1" ]; then
        would_do print "the steps to switch from $cur to $target"
        STAGE_DETAIL="$target; the steps are printed at the end"
        return "$ST_OK"
    fi

    bin="$(command -v "$target" 2>/dev/null || true)"
    if [ -z "$bin" ]; then
        warn "$target is not installed"
        note "install it: $(pm_plan "$(shell_package "$target")")"
        STAGE_DETAIL="$target is not installed"
        return "$ST_WARN"
    fi
    if [ "$target" = "$cur" ]; then
        STAGE_DETAIL="$target is already your login shell"
    else
        STAGE_DETAIL="$target at $bin; switch with the steps at the end"
    fi
    return "$ST_OK"
}

# The closing instructions. Printed, never run.
print_shell_steps() {
    local cur target bin rel cdisp f=""

    cur="$(current_shell)"
    target="$(target_shell)"
    [ -n "$target" ] || return 0
    bin="$(command -v "$target" 2>/dev/null || true)"

    # $HOME-relative forms of the config dir: one for reading, one to paste.
    case "$CONFIG_DIR" in
        "$HOME"/*) cdisp="~${CONFIG_DIR#"$HOME"}"; rel="\$HOME${CONFIG_DIR#"$HOME"}" ;;
        *)         cdisp="$CONFIG_DIR";            rel="$CONFIG_DIR" ;;
    esac

    printf '\n'
    if [ "$SHELL_CHOICE" != "keep" ] && [ -n "$SHELL_CHOICE" ] && [ "$target" != "$cur" ]; then
        note "Switch your login shell from $cur to $target. This is not done for you:"
        note "it needs your password and takes effect at your next login."
        if [ -z "$bin" ]; then
            note "  0. $target is not installed yet: $(pm_plan "$(shell_package "$target")")"
            bin="/usr/bin/$target"
        fi
        dim "  1. grep -qx $bin /etc/shells || echo $bin | $SUDO tee -a /etc/shells"
        dim "  2. chsh -s $bin"
        dim "     no chsh? use: $SUDO usermod -s $bin \$USER   (Fedora: chsh is in util-linux-user)"
        dim "  3. log out and back in, then check: getent passwd \$USER | cut -d: -f7"
        printf '\n'
    elif [ "$target" = "$cur" ]; then
        note "Your login shell is already $target, so there is nothing to switch."
        printf '\n'
    fi

    note "Hook $target up to the configs in $cdisp/$target (run once):"
    case "$target" in
        zsh)
            if [ -f "$CONFIG_DIR/zsh/.zshrc" ]; then
                dim "  echo 'export ZDOTDIR=\"$rel/zsh\"' >> ~/.zshenv"
                dim "  zsh then reads $cdisp/zsh/.zshrc itself"
            elif [ -f "$CONFIG_DIR/zsh/zshrc" ]; then
                dim "  echo '[ -f $rel/zsh/zshrc ] && . $rel/zsh/zshrc' >> ~/.zshrc"
            elif [ -n "$(ls -A "$CONFIG_DIR/zsh" 2>/dev/null)" ]; then
                dim "  the startup files in $cdisp/zsh are not named .zshrc or zshrc;"
                dim "  source the right one from ~/.zshrc"
            else
                dim "  no zsh config was deployed, so there is nothing to hook up"
            fi
            ;;
        bash)
            if [ -f "$CONFIG_DIR/bash/.bashrc" ]; then f=".bashrc"; fi
            if [ -z "$f" ] && [ -f "$CONFIG_DIR/bash/bashrc" ]; then f="bashrc"; fi
            if [ -n "$f" ]; then
                dim "  echo '[ -f $rel/bash/$f ] && . $rel/bash/$f' >> ~/.bashrc"
                dim "  login shells read ~/.bash_profile: make sure it sources ~/.bashrc"
            elif [ -n "$(ls -A "$CONFIG_DIR/bash" 2>/dev/null)" ]; then
                dim "  the startup files in $cdisp/bash are not named .bashrc or bashrc;"
                dim "  source the right one from ~/.bashrc"
            else
                dim "  no bash config was deployed, so there is nothing to hook up"
            fi
            ;;
    esac
    return 0
}
