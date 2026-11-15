#!/bin/sh
#
# Silhouette installer: orchestration & POSIX entry point.
#
# Goal: deploy this repo's configs into ~/.config so that either all of it
# lands or ~/.config is left exactly as it was found.
#
# Entry point is written in standard POSIX sh (/bin/sh) so that it runs out of
# the box across *nix and *BSD distributions (FreeBSD, OpenBSD, NetBSD, macOS,
# Alpine, Void, Arch, Debian/Ubuntu, Fedora, etc.).
#
# The POSIX entrypoint checks for prerequisites needed by the modular
# installer (primarily bash >= 4.4 and git), automatically installs them using
# the host system's package manager if missing, and then hands off execution to
# the modular installer.
#
# Usage:
#   ./install.sh [options]
#   sh install.sh [options]
#   curl -fsSL <repo>/install.sh | sh -s -- [options]
#   ./install.sh --rollback [STAMP]

set -eu

INSTALLER_VERSION="2.0.0"

REPO_URL="${SILHOUETTE_REPO:-https://github.com/Triangulation5/.config.git}"
REF="${SILHOUETTE_REF:-main}"
DEFAULT_SRC="${XDG_DATA_HOME:-${HOME:-}/.local/share}/silhouette-install"

# Determine script location if available
THIS_SCRIPT="$0"
case "$THIS_SCRIPT" in
    /*) ;;
    *)
        if [ -f "$THIS_SCRIPT" ]; then
            _script_dir="$(cd -- "$(dirname -- "$THIS_SCRIPT")" 2>/dev/null && pwd)"
            THIS_SCRIPT="$_script_dir/$(basename -- "$THIS_SCRIPT")"
            unset _script_dir
        fi
        ;;
esac

SCRIPT_DIR=""
if [ -f "$THIS_SCRIPT" ]; then
    SCRIPT_DIR="$(dirname -- "$THIS_SCRIPT")"
fi

INSTALLER_DIR=""
if [ -n "$SCRIPT_DIR" ]; then
    for _dir in "$SCRIPT_DIR/installer" "$SCRIPT_DIR/scripts/installer"; do
        if [ -f "$_dir/lib/ui.sh" ]; then
            INSTALLER_DIR="$_dir"
            break
        fi
    done
    unset _dir
fi

# Detect whether the current executing shell is already bash 4.4+
_in_good_bash=0
case "${BASH_VERSION:-}" in
    4.[4-9]*|[5-9].*)
        _in_good_bash=1
        ;;
esac

detect_posix_os() {
    OS="$(uname -s 2>/dev/null || echo "Unknown")"
    FAMILY="unknown"
    PM=""

    case "$OS" in
        FreeBSD)
            FAMILY="freebsd"
            PM="pkg"
            ;;
        OpenBSD)
            FAMILY="openbsd"
            PM="pkg_add"
            ;;
        NetBSD)
            FAMILY="netbsd"
            PM="pkgin"
            ;;
        DragonFly)
            FAMILY="dragonfly"
            PM="pkg"
            ;;
        Darwin)
            FAMILY="darwin"
            if command -v brew >/dev/null 2>&1; then
                PM="brew"
            elif command -v port >/dev/null 2>&1; then
                PM="port"
            fi
            ;;
        Linux)
            _id=""
            _like=""
            if [ -r /etc/os-release ]; then
                _os_info="$( . /etc/os-release >/dev/null 2>&1 && printf '%s|%s' "${ID:-}" "${ID_LIKE:-}" )" || _os_info="|"
                _id="${_os_info%%|*}"
                _like="${_os_info#*|}"
            fi

            case " $_id $_like " in
                *fedora*|*rhel*|*centos*|*rocky*|*alma*) FAMILY="fedora" ;;
                *alpine*)                                 FAMILY="alpine" ;;
                *artix*)                                  FAMILY="artix" ;;
                *arch*)                                   FAMILY="arch" ;;
                *debian*|*ubuntu*|*pop*|*mint*)           FAMILY="debian" ;;
                *suse*)                                   FAMILY="suse" ;;
                *gentoo*)                                 FAMILY="gentoo" ;;
                *void*)                                   FAMILY="void" ;;
                *solus*)                                  FAMILY="solus" ;;
                *nixos*|*nix*)                            FAMILY="nix" ;;
                *)
                    if command -v pacman >/dev/null 2>&1; then FAMILY="arch"
                    elif command -v apt-get >/dev/null 2>&1; then FAMILY="debian"
                    elif command -v dnf >/dev/null 2>&1; then FAMILY="fedora"
                    elif command -v apk >/dev/null 2>&1; then FAMILY="alpine"
                    elif command -v xbps-install >/dev/null 2>&1; then FAMILY="void"
                    elif command -v zypper >/dev/null 2>&1; then FAMILY="suse"
                    elif command -v emerge >/dev/null 2>&1; then FAMILY="gentoo"
                    fi
                    ;;
            esac

            case "$FAMILY" in
                fedora)
                    if command -v dnf >/dev/null 2>&1; then PM="dnf"; else PM="yum"; fi
                    ;;
                alpine) PM="apk" ;;
                arch|artix) PM="pacman" ;;
                debian) PM="apt-get" ;;
                suse)   PM="zypper" ;;
                gentoo) PM="emerge" ;;
                void)   PM="xbps" ;;
                solus)  PM="eopkg" ;;
                nix)    PM="nix-env" ;;
                *)      PM="" ;;
            esac
            ;;
    esac
}

detect_elevation() {
    ELEVATE=""
    if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
        ELEVATE="root"
    elif command -v sudo >/dev/null 2>&1; then
        ELEVATE="sudo"
    elif command -v doas >/dev/null 2>&1; then
        ELEVATE="doas"
    elif command -v su >/dev/null 2>&1; then
        ELEVATE="su"
    else
        ELEVATE="none"
    fi
}

run_privileged() {
    case "$ELEVATE" in
        root)
            "$@"
            ;;
        sudo)
            sudo "$@"
            ;;
        doas)
            doas "$@"
            ;;
        su)
            _cmd=""
            for _arg in "$@"; do
                _cmd="${_cmd:+${_cmd} }'$_arg'"
            done
            su -c "$_cmd"
            ;;
        *)
            printf '%s\n' "  x Root privilege or sudo/doas is required to install packages." >&2
            return 1
            ;;
    esac
}

is_good_bash() {
    _cand="${1:-}"
    [ -n "$_cand" ] || return 1
    [ -x "$_cand" ] || return 1
    _cand_ver="$("$_cand" -c 'printf "%s" "${BASH_VERSION:-}"' 2>/dev/null || true)"
    case "$_cand_ver" in
        4.[4-9]*|[5-9].*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

find_good_bash() {
    GOOD_BASH=""
    for _path in \
        "${BASH:-}" \
        "$(command -v bash 2>/dev/null || true)" \
        /usr/local/bin/bash \
        /usr/pkg/bin/bash \
        /opt/homebrew/bin/bash \
        /bin/bash \
        /usr/bin/bash
    do
        if is_good_bash "$_path"; then
            GOOD_BASH="$_path"
            return 0
        fi
    done
    return 1
}

ensure_prerequisites() {
    _missing_pkgs=""

    if ! find_good_bash; then
        _missing_pkgs="bash"
    fi

    if ! command -v git >/dev/null 2>&1; then
        _missing_pkgs="${_missing_pkgs:+${_missing_pkgs} }git"
    fi

    [ -n "$_missing_pkgs" ] || return 0

    printf '%s\n' "==> Silhouette installer requires: $_missing_pkgs"
    detect_posix_os
    detect_elevation

    if [ "$ELEVATE" = "none" ] && [ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]; then
        printf '%s\n' "  x Cannot install missing prerequisites ($_missing_pkgs) without root, sudo, or doas." >&2
        printf '%s\n' "    Please install them manually using your package manager and run install.sh again." >&2
        exit 1
    fi

    printf '%s\n' "==> Installing $_missing_pkgs using ${PM:-system package manager}..."
    case "$PM" in
        pkg)
            run_privileged env ASSUME_ALWAYS_YES=YES pkg install -y $_missing_pkgs
            ;;
        pkg_add)
            run_privileged pkg_add -I $_missing_pkgs
            ;;
        pkgin)
            run_privileged pkgin -y install $_missing_pkgs
            ;;
        apk)
            run_privileged apk add --no-cache $_missing_pkgs
            ;;
        pacman)
            run_privileged pacman -Sy --needed --noconfirm $_missing_pkgs
            ;;
        apt-get)
            run_privileged apt-get update -y
            run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y $_missing_pkgs
            ;;
        dnf)
            run_privileged dnf install -y $_missing_pkgs
            ;;
        yum)
            run_privileged yum install -y $_missing_pkgs
            ;;
        zypper)
            run_privileged zypper --non-interactive in $_missing_pkgs
            ;;
        xbps)
            run_privileged xbps-install -Sy $_missing_pkgs
            ;;
        emerge)
            _atoms=""
            for _p in $_missing_pkgs; do
                case "$_p" in
                    bash) _atoms="${_atoms:+${_atoms} }app-shells/bash" ;;
                    git)  _atoms="${_atoms:+${_atoms} }dev-vcs/git" ;;
                    *)    _atoms="${_atoms:+${_atoms} }$_p" ;;
                esac
            done
            run_privileged emerge --ask=n --oneshot $_atoms
            ;;
        brew)
            brew install $_missing_pkgs
            ;;
        eopkg)
            run_privileged eopkg install -y $_missing_pkgs
            ;;
        nix-env)
            for _p in $_missing_pkgs; do
                nix-env -iA "nixpkgs.$_p"
            done
            ;;
        *)
            printf '%s\n' "  x Unrecognized package manager. Please install $_missing_pkgs manually and re-run." >&2
            exit 1
            ;;
    esac

    if ! find_good_bash; then
        printf '%s\n' "  x bash (>= 4.4) was not found even after installation." >&2
        exit 1
    fi
}

print_posix_help() {
    printf '%s\n' "Silhouette installer $INSTALLER_VERSION"
    printf '%s\n' ""
    printf '%s\n' "Deploys the dotfiles into ~/.config as one transaction."
    printf '%s\n' ""
    printf '%s\n' "Usage:"
    printf '%s\n' "  ./install.sh [options]"
    printf '%s\n' "  sh install.sh [options]"
    printf '%s\n' "  curl -fsSL <repo>/install.sh | sh -s -- [options]"
    printf '%s\n' "  ./install.sh --rollback [STAMP]"
    printf '%s\n' ""
    printf '%s\n' "Options include --full, --core, --keep-monitors, --quickstart, --dry-run, --rollback."
    printf '%s\n' "Note: Complete option documentation is available once prerequisites (bash 4.4+) are present."
}

# If user asked for -h, --help, or --version without bash available, handle gracefully
for _arg in "$@"; do
    case "$_arg" in
        -h|--help)
            if ! find_good_bash; then
                print_posix_help
                exit 0
            fi
            ;;
        --version)
            printf '%s\n' "Silhouette installer $INSTALLER_VERSION"
            exit 0
            ;;
    esac
done

posix_bootstrap() {
    _dir="$DEFAULT_SRC"
    _ref="$REF"
    _src=""
    _temp=0
    _skip=0
    _prev=""

    for _arg in "$@"; do
        if [ "$_skip" -eq 1 ]; then
            case "$_prev" in
                --dir)    _dir="$_arg" ;;
                --source) _src="$_arg" ;;
                --ref)    _ref="$_arg" ;;
            esac
            _skip=0
            continue
        fi
        case "$_arg" in
            --dir=*)    _dir="${_arg#*=}" ;;
            --source=*) _src="${_arg#*=}" ;;
            --ref=*)    _ref="${_arg#*=}" ;;
            --dir|--source|--ref)
                _prev="$_arg"
                _skip=1
                ;;
            --dry-run|-h|--help|--version)
                _temp=1
                ;;
        esac
    done

    if [ -n "${SILHOUETTE_BOOTSTRAPPED:-}" ]; then
        printf '%s\n' "  x installer modules not found next to $0 (neither installer/ nor scripts/installer/ exists in that checkout)." >&2
        exit 1
    fi
    [ -n "${HOME:-}" ] || { printf '%s\n' "  x HOME is not set" >&2; exit 1; }
    export SILHOUETTE_BOOTSTRAPPED=1

    ensure_prerequisites

    if [ -n "$_src" ]; then
        if [ ! -f "$_src/install.sh" ] || { [ ! -d "$_src/installer" ] && [ ! -d "$_src/scripts/installer" ]; }; then
            printf '%s\n' "  x --source $_src has no installer/ directory; is it a current checkout?" >&2
            exit 1
        fi
        _root="$_src"
        exec "$GOOD_BASH" "$_root/install.sh" "$@"
    else
        if ! command -v git >/dev/null 2>&1; then
            printf '%s\n' "  x git is needed to fetch the installer; install it, or pass --source PATH" >&2
            exit 1
        fi
        printf '%s\n' "==> fetching the installer"
        if [ -d "$_dir/.git" ] && [ "$_temp" = "1" ]; then
            _root="$_dir"
            exec "$GOOD_BASH" "$_root/install.sh" "$@"
        elif [ "$_temp" = "1" ]; then
            _tmp="$(mktemp -d)"
            trap 'rm -rf -- "$_tmp"' EXIT
            git clone --quiet --depth 1 --branch "$_ref" -- "$REPO_URL" "$_tmp" \
                || { printf '%s\n' "  x could not clone $REPO_URL ($_ref)" >&2; exit 1; }
            _root="$_tmp"
            "$GOOD_BASH" "$_root/install.sh" "$@"
            _rc=$?
            rm -rf -- "$_tmp"
            trap - EXIT
            exit "$_rc"
        elif [ -d "$_dir/.git" ]; then
            git -C "$_dir" fetch --quiet --depth 1 origin "$_ref" \
                || printf '%s\n' "  ! could not fetch $_ref; using the clone as it is" >&2
            git -C "$_dir" merge --quiet --ff-only FETCH_HEAD >/dev/null 2>&1 \
                || printf '%s\n' "  ! $_dir has local changes; using them as they are" >&2
            _root="$_dir"
            exec "$GOOD_BASH" "$_root/install.sh" "$@"
        elif [ -e "$_dir" ] && [ -n "$(ls -A "$_dir" 2>/dev/null)" ]; then
            printf '%s\n' "  x $_dir exists and is not a git checkout. Pass --dir or --source." >&2
            exit 1
        else
            mkdir -p -- "$(dirname -- "$_dir")"
            git clone --quiet --depth 1 --branch "$_ref" -- "$REPO_URL" "$_dir" \
                || { printf '%s\n' "  x could not clone $REPO_URL ($_ref)" >&2; exit 1; }
            _root="$_dir"
            exec "$GOOD_BASH" "$_root/install.sh" "$@"
        fi
    fi
}

if [ -z "$INSTALLER_DIR" ]; then
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/hypr/hyprland.lua" ]; then
        printf '%s\n' "  x installer modules not found. Looked in:" \
            "      $SCRIPT_DIR/installer" \
            "      $SCRIPT_DIR/scripts/installer" \
            "    Put the installer/ directory from the zip next to install.sh." >&2
        exit 1
    fi
    posix_bootstrap "$@"
fi

# If we are not currently running under a supported version of bash,
# install/verify prerequisites and re-exec with bash.
if [ "$_in_good_bash" -eq 0 ]; then
    ensure_prerequisites
    find_good_bash || {
        printf '%s\n' "  x bash (>= 4.4) is required to run the installer." >&2
        exit 1
    }
    exec "$GOOD_BASH" "$THIS_SCRIPT" "$@"
fi

# ---- modular installer (running under bash 4.4+) -------------------------------
set -euo pipefail

for _module in \
    lib/ui lib/util lib/prompt lib/txn lib/stage \
    config cli packages distro gentoo \
    stages/preflight stages/source stages/plan stages/deps stages/deploy \
    stages/extras stages/shell stages/report stages/assets stages/rollback
do
    if [ ! -f "$INSTALLER_DIR/$_module.sh" ]; then
        printf '%s\n' "  x installer module missing: $INSTALLER_DIR/$_module.sh" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    . "$INSTALLER_DIR/$_module.sh"
done
unset _module

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

    STAMP="$(date +%Y%m%d-%H%M%S)"
    _base="$STAMP"; _n=1
    while [ -e "$STATE_DIR/backups/$STAMP" ]; do
        _n=$((_n + 1)); STAMP="$_base-$_n"
    done
    BACKUP_DIR="$STATE_DIR/backups/$STAMP"
    LOG_DIR="$STATE_DIR/logs/$STAMP"
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
    stage optional "Install selected assets" stage_assets

    # The transaction. Everything between begin and commit is undone together.
    stage required "Begin transaction"     stage_txn_begin
    stage required "Deploy configs"        stage_deploy_configs
    stage required "Rewrite home paths"    stage_home_paths
    stage required "Set script modes"      stage_script_modes
    stage required "Monitor layout"        stage_monitors
    stage required "Apply appearance settings" stage_asset_settings
    stage required "Commit transaction"    stage_txn_commit

    # After the commit: a failure here cannot undo the dotfiles.
    stage optional "Install st terminal"   stage_st
    stage optional "Install rishot"        stage_rishot
    stage optional "Install Flatpak apps"  stage_flatpaks
    stage optional "Install GRUB theme"    stage_grub_theme
    stage optional "Install Pi harness"    stage_pi_harness
    stage optional "Install Ollama"        stage_ollama
    stage optional "Check runtime tools"   stage_report_tools
    stage optional "Check init system"     stage_report_init
    stage optional "Check shell"           stage_shell

    finish
}

main "$@"
