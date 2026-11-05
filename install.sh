#!/usr/bin/env bash
#
# Silhouette installer: orchestration only.
#
# Goal: deploy this repo's configs into ~/.config so that either all of it
# lands or ~/.config is left exactly as it was found.
#
# This file decides which stages run and in what order. What each stage does
# lives in installer/ next to this file (see its README). Every stage reports how it went:
#
#     [   Ok   ] Detect system (arch, via pacman)
#     [ Failed ] Deploy configs (1 of 19 entries failed)
#
# The rules the installer holds itself to:
#
#   1. Nothing is written to ~/.config until the plan has been printed and you
#      have agreed to it. Piping into `bash` means stdin is the script, not a
#      keyboard, so prompts read from /dev/tty and a missing terminal is an
#      error, never a silent yes. --yes is the explicit "I read the plan" flag.
#   2. The config changes are one transaction. Every path is recorded in a
#      journal, and saved if it already existed, BEFORE it is touched. If a
#      required stage fails, or you press Ctrl-C, or the script dies, the
#      journal is replayed in reverse and ~/.config is as it was. A finished
#      install can be undone later with --rollback. Files the installer has no
#      opinion about are left alone: directories are merged into, never
#      deleted and recreated.
#   3. Packages and third-party installers (rishot) are outside that
#      transaction, because a package manager cannot be rolled back from here.
#      They are best effort: a failed batch is retried one package at a time, a
#      name that does not resolve is reported, and a failure there never rolls
#      back the dotfiles.
#   4. Hardware-specific config is neutralised. The monitor layout becomes one
#      preferred-mode output and the original is kept as monitors.lua.example;
#      /home/josh paths are rewritten to $HOME.
#   5. --dry-run touches nothing outside a temp directory. It walks the same
#      code path as a real run, printing every command instead of running it.
#   6. Exit status: 0 done, 1 stopped (config rolled back), 2 bad usage,
#      3 done but an optional stage failed.
#
# Layout: install.sh and installer/ sit at the top of the repo, which is
# ~/.config itself, so after an install they live at ~/.config/install.sh and
# ~/.config/installer/*.sh and can be run from there (--rollback, re-runs).
#
# Usage is in --help.

# This installer is bash: arrays, namerefs and pipefail are not accidentals.
# If someone runs `sh install.sh`, say what to install instead of dying on a
# syntax error hundreds of lines later. These tests are themselves POSIX.
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' "install.sh needs bash. Alpine: apk add bash; Void: xbps-install -S bash" >&2
    exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    printf '%s\n' "install.sh needs bash 4.4 or newer (this is bash $BASH_VERSION)." >&2
    exit 1
fi

set -euo pipefail

INSTALLER_VERSION="2.0.0"

# These three are here, not in config.sh, because the bootstrap below needs
# them before the modules can be loaded.
REPO_URL="${SILHOUETTE_REPO:-https://github.com/Triangulation5/.config.git}"
REF="${SILHOUETTE_REF:-main}"
# `silhouette-install` for everything this script owns, leaving plain
# `silhouette` to the shell. The shell keeps its own data under
# ~/.local/share/silhouette (the AppImage registry and icons) and its own state
# under ~/.local/state/silhouette, so a clone in either path would sit inside
# files the shell reads and writes.
DEFAULT_SRC="${XDG_DATA_HOME:-${HOME:-}/.local/share}/silhouette-install"

# ---- bootstrap ----------------------------------------------------------------
#
# `curl ... | bash` and a bare downloaded install.sh have no installer/ directory
# next to them. Fetch the repo, then hand over to the install.sh inside it, so
# the installer that runs is always the one that matches the files it deploys.
# Only the options that decide where that checkout comes from are read here;
# the real parser in cli.sh sees all of them afterwards.
bootstrap() {
    local dir="$DEFAULT_SRC" ref="$REF" src="" temp=0 tmp="" root rc=0
    local -a args=("$@")

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dir)    dir="${2:-}"; [ "$#" -gt 1 ] && shift ;;
            --source) src="${2:-}"; [ "$#" -gt 1 ] && shift ;;
            --ref)    ref="${2:-}"; [ "$#" -gt 1 ] && shift ;;
            # These must not write anywhere, so they use a throwaway checkout.
            --dry-run|-h|--help|--version) temp=1 ;;
        esac
        shift
    done

    if [ -n "${SILHOUETTE_BOOTSTRAPPED:-}" ]; then
        printf '%s\n' "  x installer modules not found next to $0 (neither installer/ nor scripts/installer/ exists in that checkout)." >&2
        exit 1
    fi
    [ -n "${HOME:-}" ] || { printf '%s\n' "  x HOME is not set" >&2; exit 1; }
    export SILHOUETTE_BOOTSTRAPPED=1

    if [ -n "$src" ]; then
        if [ ! -f "$src/install.sh" ] || { [ ! -d "$src/installer" ] && [ ! -d "$src/scripts/installer" ]; }; then
            printf '%s\n' "  x --source $src has no installer/ directory; is it a current checkout?" >&2
            exit 1
        fi
        root="$src"
    else
        if ! command -v git >/dev/null 2>&1; then
            printf '%s\n' "  x git is needed to fetch the installer; install it, or pass --source PATH" >&2
            exit 1
        fi
        printf '%s\n' "==> fetching the installer"
        if [ -d "$dir/.git" ] && [ "$temp" = "1" ]; then
            root="$dir"                       # read-only runs use it as it is
        elif [ "$temp" = "1" ]; then
            tmp="$(mktemp -d)"
            trap 'rm -rf -- "$tmp"' EXIT
            git clone --quiet --depth 1 --branch "$ref" -- "$REPO_URL" "$tmp" \
                || { printf '%s\n' "  x could not clone $REPO_URL ($ref)" >&2; exit 1; }
            root="$tmp"
        elif [ -d "$dir/.git" ]; then
            git -C "$dir" fetch --quiet --depth 1 origin "$ref" \
                || printf '%s\n' "  ! could not fetch $ref; using the clone as it is" >&2
            git -C "$dir" merge --quiet --ff-only FETCH_HEAD >/dev/null 2>&1 \
                || printf '%s\n' "  ! $dir has local changes; using them as they are" >&2
            root="$dir"
        elif [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            printf '%s\n' "  x $dir exists and is not a git checkout. Pass --dir or --source." >&2
            exit 1
        else
            mkdir -p -- "$(dirname -- "$dir")"
            git clone --quiet --depth 1 --branch "$ref" -- "$REPO_URL" "$dir" \
                || { printf '%s\n' "  x could not clone $REPO_URL ($ref)" >&2; exit 1; }
            root="$dir"
        fi
    fi

    # Not exec: the trap above has a temp directory to remove afterwards.
    bash "$root/install.sh" "${args[@]}" || rc=$?
    exit "$rc"
}

# A script that is a real file knows where it lives; one read from a pipe
# (curl | bash) or /dev/fd (bash <(curl ...)) does not.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fi
# The modules live in installer/ next to this file. scripts/installer/ is where
# the first release put them; it is still found, so an old tree keeps working
# until it is moved (mv scripts/installer installer).
INSTALLER_DIR=""
if [ -n "$SCRIPT_DIR" ]; then
    for _dir in "$SCRIPT_DIR/installer" "$SCRIPT_DIR/scripts/installer"; do
        if [ -f "$_dir/lib/ui.sh" ]; then INSTALLER_DIR="$_dir"; break; fi
    done
    unset _dir
fi

if [ -z "$INSTALLER_DIR" ]; then
    # Inside a config checkout the modules are simply missing. Say so rather
    # than fetching a different copy of the repo, which may be older and would
    # fail with a more confusing message.
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/hypr/hyprland.lua" ]; then
        printf '%s\n' "  x installer modules not found. Looked in:" \
            "      $SCRIPT_DIR/installer" \
            "      $SCRIPT_DIR/scripts/installer" \
            "    Put the installer/ directory from the zip next to install.sh." >&2
        exit 1
    fi
    bootstrap "$@"
fi

# ---- modules ------------------------------------------------------------------
#
# Sourced at the top level (not in a function) so the associative arrays they
# declare are global. Modules declare functions and data only; nothing runs
# until main does.
for _module in \
    lib/ui lib/util lib/prompt lib/txn lib/stage \
    config cli packages distro gentoo \
    stages/preflight stages/source stages/plan stages/deps stages/deploy \
    stages/extras stages/shell stages/report stages/rollback
do
    if [ ! -f "$INSTALLER_DIR/$_module.sh" ]; then
        printf '%s\n' "  x installer module missing: $INSTALLER_DIR/$_module.sh" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    . "$INSTALLER_DIR/$_module.sh"
done
unset _module

# ---- the run ------------------------------------------------------------------

finish() {
    summary
    if [ "$MODE" = "install" ]; then
        print_next_steps
    fi
    if [ "$NONFATAL_FAILURES" -gt 0 ]; then
        printf '\n'
        warn "finished, but $NONFATAL_FAILURES optional stage(s) failed (see above). Exit status 3."
        exit 3
    fi
    exit 0
}

main() {
    parse_args "$@"

    # One directory per run. A second run in the same second gets -2, -3, ...
    # (which still sorts after the first, so "latest" stays the latest).
    STAMP="$(date +%Y%m%d-%H%M%S)"
    _base="$STAMP"; _n=1
    while [ -e "$STATE_DIR/backups/$STAMP" ]; do
        _n=$((_n + 1)); STAMP="$_base-$_n"
    done
    BACKUP_DIR="$STATE_DIR/backups/$STAMP"
    TMP_SRC=""
    install_traps

    if [ "$DRY_RUN" = "1" ]; then
        say "${BOLD}Silhouette installer $INSTALLER_VERSION${RESET} ${YELLOW}(dry run: nothing will be written)${RESET}"
    else
        say "${BOLD}Silhouette installer $INSTALLER_VERSION${RESET}"
    fi
    printf '\n'

    stage required "Preflight checks"      stage_preflight

    if [ "$MODE" = "rollback" ]; then
        stage required "Roll back install" stage_rollback
        finish
    fi

    stage required "Detect system"         stage_detect
    stage required "Fetch source"          stage_source
    stage required "Review plan"           stage_plan

    # Outside the transaction: best effort.
    stage optional "Bootstrap tools"       stage_bootstrap_tools
    stage optional "Enable package repos"  stage_repos
    stage optional "Install packages"      stage_packages
    stage optional "Verify hyprctl"        stage_hyprctl

    # The transaction. Everything between begin and commit is undone together.
    stage required "Begin transaction"     stage_txn_begin
    stage required "Deploy configs"        stage_deploy_configs
    stage required "Rewrite home paths"    stage_home_paths
    stage required "Set script modes"      stage_script_modes
    stage required "Monitor layout"        stage_monitors
    stage required "Commit transaction"    stage_txn_commit

    # After the commit: a failure here cannot undo the dotfiles.
    stage optional "Install rishot"        stage_rishot
    stage optional "Install RetroArch"     stage_retroarch
    stage optional "Install Sioyek"        stage_sioyek
    stage optional "Install GRUB theme"    stage_grub_theme
    stage optional "Check runtime tools"   stage_report_tools
    stage optional "Check init system"     stage_report_init
    stage optional "Check shell"           stage_shell

    finish
}

main "$@"
