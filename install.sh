#!/usr/bin/env bash
#
# Silhouette installer.
#
# Deploys this repo's configs into ~/.config, after backing up whatever is
# already there. The rules the script holds itself to:
#
#   1. Nothing is written to ~/.config until the plan has been printed and you
#      have agreed to it. Piping into `bash` means stdin is the script, not a
#      keyboard, so prompts read from /dev/tty and a missing terminal is an
#      error, never a silent yes. --yes is the explicit "I read the plan" flag.
#   2. Every path it replaces is copied to
#      ~/.local/state/silhouette-install/backups/<timestamp>/ first, so a bad install
#      is a `cp -a` away from undone. Files it has no opinion about are left
#      alone: directories are merged into, never deleted and recreated.
#   3. Hardware-specific config is neutralised. The monitor layout becomes one
#      preferred-mode output and the original is kept as
#      monitors.lua.example; /home/josh paths are rewritten to $HOME.
#   4. The dependency step is best effort. Package names differ per distro and
#      move between releases, so a failed batch is retried one package at a
#      time and a name that does not resolve is reported, not fatal. A missing
#      optional tool degrades one shell feature, it does not stop the install.
#   5. --dry-run touches nothing outside a temp directory. It walks the same
#      code path as a real run, printing every command instead of running it.
#
# Usage is in --help, or in the README's Install section.

# This installer is bash: arrays, namerefs and pipefail are not accidentals.
# If someone runs `sh install.sh`, say what to install instead of dying on a
# syntax error hundreds of lines later. This test is itself POSIX.
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' "install.sh needs bash. Alpine: apk add bash; Void: xbps-install -S bash" >&2
    exit 1
fi

set -euo pipefail

INSTALLER_VERSION="1.0.0"
REPO_URL="${SILHOUETTE_REPO:-https://github.com/Triangulation5/.config.git}"
REF="${SILHOUETTE_REF:-main}"
# `silhouette-install` for everything this script owns, leaving plain
# `silhouette` to the shell. The shell keeps its own data under
# ~/.local/share/silhouette (the AppImage registry and icons) and its own state
# under ~/.local/state/silhouette, so a clone in either path would sit inside
# files the shell reads and writes.
DEFAULT_SRC="${XDG_DATA_HOME:-$HOME/.local/share}/silhouette-install"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
# Deliberately `silhouette-install`, not `silhouette`: the shell owns
# ~/.local/state/silhouette itself (its flags, its calendar, its own backups),
# and two sets of backups sharing one directory would each read the other's
# files as their own.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette-install"

# Top-level entries in the repo that belong in ~/.config. install.sh itself,
# the README and .gitignore are deliberately not here: they are repo furniture,
# not config. Neither are the machine-local ones .gitignore keeps out of the
# repo - rygel.conf and QtProject.conf belong to the packages that own them on
# each machine, so there is nothing here to deploy. mpd is here for its
# configuration alone: the library database, the log, the pid and the session
# state are ignored beside it, so a clone carries the conf and nothing else.
# Keep this in sync when a new top-level config lands.
CONFIG_ENTRIES=(
    bash btop cava fastfetch hypr kitty mpd ncmpcpp nvim nwg-look
    quickshell rishot sioyek tmux vim xsettingsd yazi zsh
    user-dirs.dirs user-dirs.locale
)

# Configs that hardcode the original author's home. Rewritten to $HOME after
# deploy, otherwise btop reads a nonexistent path and hypridle locks a machine
# that does not exist.
HOME_REWRITE=(
    btop/btop.conf
    hypr/hypridle.conf
)

# Core packages: what the session and the shell actually call out to. Names are
# per distro family because they genuinely differ (libnotify vs libnotify-bin,
# python3-dbus vs python-dbus).
# shellcheck disable=SC2034 # selected through the CORE_${FAMILY} nameref
CORE_fedora=(hyprland kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify slurp NetworkManager neovim bluez upower
    wireplumber xdg-utils ffmpeg ImageMagick python3-dbus)
# shellcheck disable=SC2034
CORE_arch=(hyprland kitty jq curl python brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify slurp networkmanager neovim bluez upower
    wireplumber xdg-utils ffmpeg imagemagick python-dbus)
# shellcheck disable=SC2034
CORE_debian=(hyprland kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify-bin slurp network-manager neovim bluez upower
    wireplumber xdg-utils ffmpeg imagemagick python3-dbus)
# shellcheck disable=SC2034
CORE_suse=(hyprland kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify-tools slurp NetworkManager neovim bluez upower
    wireplumber xdg-utils ffmpeg ImageMagick python3-dbus-python)
# Gentoo takes full category/package atoms, and three of these are not in
# ::gentoo at all: Hyprland was dropped from the main tree in 2026 and now
# lives in the hyproverlay repository, and brightnessctl, cliphist and
# quickshell are in GURU. GENTOO_REPO_OF below records which overlay each one
# needs, so the report can say what to enable instead of letting emerge fail
# with "no ebuilds to satisfy". Quickshell is in the list because, unlike on
# most distros, it is packaged.
# shellcheck disable=SC2034
CORE_gentoo=(gui-wm/hyprland gui-apps/quickshell x11-terms/kitty app-misc/jq
    net-misc/curl dev-lang/python app-misc/brightnessctl app-misc/ddcutil
    media-sound/cava media-sound/playerctl app-misc/cliphist
    gui-apps/wl-clipboard x11-libs/libnotify gui-apps/slurp
    net-misc/networkmanager app-editors/neovim net-wireless/bluez sys-power/upower
    media-video/wireplumber x11-misc/xdg-utils media-video/ffmpeg
    media-gfx/imagemagick dev-python/dbus-python)
# Alpine's stable repos carry the desktop stack in community, but cava and
# cliphist only exist in edge/testing. They are left out on purpose: pulling a
# testing repo in would make an install less predictable than a missing
# visualiser, and report_missing names them at the end instead.
# shellcheck disable=SC2034
CORE_alpine=(hyprland kitty jq curl python3 brightnessctl ddcutil playerctl
    wl-clipboard libnotify slurp networkmanager neovim bluez upower
    wireplumber xdg-utils ffmpeg imagemagick py3-dbus)
# Hyprland is not in Void's official repositories (see the hyprland-void repo
# in report_missing). Everything else here is in the current repo, spelled the
# way xbps spells it: NetworkManager and ImageMagick keep their capitals, and
# the Python bindings are python3-dbus rather than dbus-python.
# shellcheck disable=SC2034
CORE_void=(kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify slurp NetworkManager neovim bluez upower
    wireplumber xdg-utils ffmpeg ImageMagick python3-dbus quickshell)
# Nothing to guess from. The generic names are listed so the report is concrete
# and the user can map them to whatever their package manager calls them.
# shellcheck disable=SC2034
CORE_unknown=(hyprland quickshell kitty jq curl python3 brightnessctl ddcutil cava
    playerctl cliphist wl-clipboard libnotify slurp networkmanager neovim bluez upower
    wireplumber xdg-utils ffmpeg imagemagick)

# --full: the daily apps on top of the core, plus yazi's helpers so the file
# manager previews instead of erroring on every file type.
# shellcheck disable=SC2034
FULL_fedora=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip fd-find ripgrep fzf zoxide bat chafa)
# shellcheck disable=SC2034
FULL_arch=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf zoxide bat chafa)
# shellcheck disable=SC2034
FULL_debian=(nautilus firefox-esr yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip-full fd-find ripgrep fzf zoxide bat chafa)
# shellcheck disable=SC2034
FULL_suse=(nautilus MozillaFirefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-tools p7zip fd ripgrep fzf zoxide bat chafa)
# yazi is GURU's; the rest are ::gentoo. poppler's `utils` USE flag (on by
# default) is what provides pdftoppm for yazi's PDF previews.
# shellcheck disable=SC2034
FULL_gentoo=(gnome-base/nautilus www-client/firefox app-misc/yazi
    media-sound/mpd media-sound/ncmpcpp sys-process/btop
    media-video/ffmpegthumbnailer app-text/poppler app-arch/p7zip sys-apps/fd
    sys-apps/ripgrep app-shells/fzf app-shells/zoxide sys-apps/bat
    media-gfx/chafa)
# Atoms that need an overlay enabled first. Anything not listed is ::gentoo.
declare -A GENTOO_REPO_OF=(
    [gui-wm/hyprland]=hyproverlay
    [gui-apps/quickshell]=guru
    [app-misc/brightnessctl]=guru
    [app-misc/cliphist]=guru
    [app-misc/yazi]=guru
)
# Alpine does not package p7zip; the upstream 7zip package provides both 7z
# and 7zz, which is what yazi looks for.
# shellcheck disable=SC2034
FULL_alpine=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils 7zip fd ripgrep fzf zoxide bat chafa)
# shellcheck disable=SC2034
FULL_void=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip fd ripgrep fzf zoxide bat chafa)
# shellcheck disable=SC2034
FULL_unknown=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf zoxide bat chafa)

# Never installed automatically: these need kernel modules, driver quirk
# handling or hardware nobody else has. Reported at the end instead.
OPTIONAL_HINTS=(
    "awww: the wallpaper daemon the scripts drive (Arch: awww / awww-git, Gentoo: gui-apps/awww in GURU, otherwise build from source)"
    "gpu-screen-recorder: hardware-encoded screen recording (Gentoo: media-video/gpu-screen-recorder in GURU, Flatpak also available)"
    "howdy: face unlock on the lockscreen, needs a camera and a PAM entry"
    "zenity or kdialog: the native folder picker for the wallpaper strip"
)

DRY_RUN=0
ASSUME_YES=0
NO_DEPS=0
FULL=0
KEEP_MONITORS=0
SRC_OVERRIDE=""
FAILED_ENTRIES=()
# Filled in by detect_privilege. Kept as a plain command name so the same
# variable works for sudo and doas, and so --dry-run can print the command it
# would really run.
SUDO="sudo"
# 0 when neither sudo nor doas exists. Only Gentoo (where the package step is
# advisory) and --dry-run get this far without one.
HAVE_PRIV=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'
    YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; YELLOW=""; RESET=""
fi

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RESET"; }
note() { printf '    %s\n' "$*"; }
dim()  { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die()  { printf '%s  x %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# run wraps every mutating command so --dry-run prints the same plan a real
# install would execute. Kept as a plain wrapper (not a string echo) so quoting
# in the original command is preserved in what gets shown.
run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '    %swould run:%s %s\n' "$DIM" "$RESET" "$*"
        return 0
    fi
    "$@"
}

usage() {
    cat <<EOF
${BOLD}Silhouette installer ${INSTALLER_VERSION}${RESET}

Usage:
  ./install.sh [options]
  curl -fsSL <repo>/install.sh | bash -s -- [options]

Options:
  -h, --help          show this help and exit
      --quickstart    core defaults, no questions (same as the default flow with --yes)
  -y, --yes           assume yes for every prompt
      --full          also install the daily apps and yazi's preview helpers
      --no-deps       skip the package step, only deploy the configs
      --dry-run       walk the whole flow and change nothing
      --keep-monitors deploy the repo's monitor layout instead of the portable default
      --dir PATH      clone and deploy from PATH (default: $DEFAULT_SRC)
      --source PATH   deploy from a clone you already have, no fetching
      --ref REF       branch or tag to fetch (default: $REF)

What it will touch:
  configs      $CONFIG_DIR
  backups      $STATE_DIR/backups/<timestamp>
  dependencies through your distro's package manager (sudo or doas)
               on Gentoo: printed as an emerge command for you to run, never emerged unasked
EOF
}

# Prompts read from /dev/tty because `curl | bash` owns stdin. With no terminal
# the only safe answer is the explicit flag, so say that rather than defaulting.
confirm() {
    local prompt="$1" reply=""
    [ "$ASSUME_YES" = "1" ] && return 0

    # Opening /dev/tty is the real test, not -r: with no controlling terminal
    # (a CI runner, a container, a pipe) the path exists but the open fails.
    # The probe runs in a subshell so the failure is silenced on that subshell's
    # own stderr; bash prints a redirection error before it would apply a
    # redirection on the failing command itself, so it cannot be quieted inline.
    if (exec 3</dev/tty) 2>/dev/null; then
        printf '%s [y/N] ' "$prompt" > /dev/tty
        read -r reply < /dev/tty || reply=""
        case "$reply" in
            [yY]*) return 0 ;;
            *) die "aborted, nothing was changed" ;;
        esac
    fi
    die "no terminal to ask on. Re-run with --yes once you have read the plan above."
}

# A yes/no for optional extras. Unlike confirm, "no" and "no terminal" are
# ordinary answers here: they skip the extra, they do not abort the install.
ask() {
    local prompt="$1" reply=""
    (exec 3</dev/tty) 2>/dev/null || return 1
    printf '%s [y/N] ' "$prompt" > /dev/tty
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        [yY]*) return 0 ;;
        *)     return 1 ;;
    esac
}

cleanup() {
    if [ -n "${TMP_SRC:-}" ] && [ -d "${TMP_SRC:-}" ]; then
        rm -rf -- "$TMP_SRC"
    fi
}
trap cleanup EXIT

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)        usage; exit 0 ;;
            --quickstart)     ASSUME_YES=1 ;;
            -y|--yes)         ASSUME_YES=1 ;;
            --full)           FULL=1 ;;
            --no-deps)        NO_DEPS=1 ;;
            --dry-run)        DRY_RUN=1 ;;
            --keep-monitors)  KEEP_MONITORS=1 ;;
            --dir)            DEFAULT_SRC="${2:?--dir needs a path}"; shift ;;
            --source)         SRC_OVERRIDE="${2:?--source needs a path}"; shift ;;
            --ref)            REF="${2:?--ref needs a branch or tag}"; shift ;;
            *)                die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done
}

detect_distro() {
    local id="" like=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        like="${ID_LIKE:-}"
    fi

    case " $id $like " in
        *fedora*|*rhel*|*centos*) FAMILY="fedora" ;;
        *alpine*)                 FAMILY="alpine" ;;
        *arch*)                   FAMILY="arch" ;;
        *debian*|*ubuntu*)        FAMILY="debian" ;;
        *suse*)                   FAMILY="suse" ;;
        *gentoo*)                 FAMILY="gentoo" ;;
        *void*)                   FAMILY="void" ;;
        *)                        FAMILY="unknown" ;;
    esac

    case "$FAMILY" in
        fedora) PM="dnf" ;;
        alpine) PM="apk" ;;
        arch)   PM="pacman" ;;
        debian) PM="apt" ;;
        suse)   PM="zypper" ;;
        gentoo) PM="emerge" ;;
        void)   PM="xbps" ;;
        *)      PM="" ;;
    esac
}

# sudo is the default on the distros this script grew up with, but Alpine and
# a fair number of Void installs use doas instead. Probe once, and only make it
# fatal on a real run: --dry-run should still print the plan on a machine with
# neither installed. On Gentoo nothing is emerged without a second, explicit
# yes, so a missing sudo is only a problem if you take that offer.
detect_privilege() {
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    elif [ "$PM" = "emerge" ]; then
        SUDO="sudo"
        HAVE_PRIV=0
    elif [ "$DRY_RUN" = "1" ]; then
        SUDO="sudo"
        HAVE_PRIV=0
        warn "neither sudo nor doas is installed; a real run would need one"
    else
        die "need sudo or doas to install packages (or re-run with --no-deps)"
    fi
}

# Alpine's archive is split: main has the base, community has hyprland, kitty,
# wireplumber and most of the desktop stack. A minimal install can enable only
# main, which would make the whole batch fail for a reason the user can fix in
# one line, so name it up front instead of after the retries.
check_distro_repos() {
    [ "$FAMILY" = "alpine" ] || return 0
    [ -r /etc/apk/repositories ] || return 0
    if ! grep -Eq '^[^#]*community/?[[:space:]]*$' /etc/apk/repositories; then
        warn "Alpine: community is not enabled in /etc/apk/repositories; most desktop packages live there."
        note "Enable it with 'setup-apkrepos', or add .../alpine/<release>/community."
    fi
}

# One package-manager invocation. Kept separate from install_packages so the
# batch can be retried per package when a single name is wrong for a release.
pm_install() {
    case "$PM" in
        dnf)    "$SUDO" dnf install -y "$@" ;;
        apk)    "$SUDO" apk add --no-cache "$@" ;;
        pacman) "$SUDO" pacman -S --needed --noconfirm "$@" ;;
        apt)    "$SUDO" apt-get install -y "$@" ;;
        zypper) "$SUDO" zypper --non-interactive install "$@" ;;
        xbps)   "$SUDO" xbps-install -Sy "$@" ;;
        *)      return 1 ;;
    esac
}

# The same invocation as a string, so --dry-run shows the real command instead
# of the name of the function that would have run it.
pm_plan() {
    case "$PM" in
        dnf)    echo "$SUDO dnf install -y $*" ;;
        apk)    echo "$SUDO apk add --no-cache $*" ;;
        pacman) echo "$SUDO pacman -S --needed --noconfirm $*" ;;
        apt)    echo "$SUDO apt-get install -y $*" ;;
        zypper) echo "$SUDO zypper --non-interactive install $*" ;;
        xbps)   echo "$SUDO xbps-install -Sy $*" ;;
        *)      echo "(no package manager detected) $*" ;;
    esac
}

# Installed means a vdb entry: /var/db/pkg/<category>/<name>-<version>. Read
# straight from disk so this works without portage-utils or gentoolkit. The
# digit after the dash keeps kitty from matching kitty-shell-integration.
gentoo_installed() {
    local d
    for d in /var/db/pkg/"$1"-[0-9]*; do
        [ -d "$d" ] && return 0
    done
    return 1
}

gentoo_repo_enabled() {
    if command -v portageq >/dev/null 2>&1; then
        portageq get_repos / 2>/dev/null | tr ' ' '\n' | grep -qx -- "$1"
        return
    fi
    [ -d "/var/db/repos/$1" ]
}

# The keyword overlay packages need on this machine (~amd64, ~arm64, ...).
gentoo_arch() {
    local a=""
    command -v portageq >/dev/null 2>&1 && a="$(portageq envvar ARCH 2>/dev/null || true)"
    if [ -z "$a" ]; then
        case "$(uname -m)" in
            x86_64)  a="amd64" ;;
            aarch64) a="arm64" ;;
            i?86)    a="x86" ;;
            riscv64) a="riscv" ;;
            *)       a="$(uname -m)" ;;
        esac
    fi
    printf '%s' "$a"
}

# Gentoo is the one family where the installer writes the plan and you run it.
# USE flags, keywords and the decision to spend an hour compiling are yours,
# so this does not feed a list to emerge behind your back. What it does do:
# drop what is already installed, name the overlays that are missing, and
# print one command that is correct for this machine. Running it is a
# separate yes, and emerge --ask then asks a third time with the real plan.
install_packages_gentoo() {
    local -a want=() repos=() overlay_atoms=()
    local atom repo arch

    for atom in "$@"; do
        gentoo_installed "$atom" && continue
        want+=("$atom")
        repo="${GENTOO_REPO_OF[$atom]:-}"
        [ -n "$repo" ] || continue
        overlay_atoms+=("$atom")
        if ! has_item "$repo" "${repos[@]}" && ! gentoo_repo_enabled "$repo"; then
            repos+=("$repo")
        fi
    done

    if [ "${#want[@]}" -eq 0 ]; then
        note "Gentoo: all $# packages are already installed"
        return 0
    fi

    note "Gentoo: ${#want[@]} of $# packages are not installed yet."
    note "Nothing is emerged for you; USE flags and keywords stay your call."

    if [ "${#repos[@]}" -gt 0 ]; then
        printf '\n'
        note "1. Enable the overlays these need:"
        gentoo_installed app-eselect/eselect-repository \
            || note "   $SUDO emerge --ask --noreplace app-eselect/eselect-repository"
        note "   $SUDO eselect repository enable ${repos[*]}"
        note "   $SUDO emaint sync$(printf -- ' -r %s' "${repos[@]}")"
    fi

    if [ "${#overlay_atoms[@]}" -gt 0 ]; then
        arch="$(gentoo_arch)"
        printf '\n'
        note "Overlay packages are usually keyworded ~$arch only. If you run stable,"
        note "accept them in /etc/portage/package.accept_keywords/silhouette:"
        for atom in "${overlay_atoms[@]}"; do
            dim "  $atom ~$arch"
        done
        if has_item gui-wm/hyprland "${overlay_atoms[@]}"; then
            note "Hyprland pulls in its own hypr* libraries from hyproverlay; emerge"
            note "--autounmask will list the extra keywords those need."
        fi
    fi

    printf '\n'
    local lead=""
    [ "${#repos[@]}" -gt 0 ] && lead="2. "
    note "${lead}$SUDO emerge --ask --noreplace --verbose ${want[*]}"

    [ "$DRY_RUN" = "1" ] && return 0
    if [ "$ASSUME_YES" = "1" ]; then
        dim "--yes does not extend to emerge; run the command above when you are ready."
        return 0
    fi
    if [ "${#repos[@]}" -gt 0 ]; then
        dim "Enable the overlays first, then run the command above (or re-run this installer)."
        return 0
    fi
    if [ "$HAVE_PRIV" != "1" ]; then
        dim "No sudo or doas here: run the command above as root."
        return 0
    fi

    printf '\n'
    if ask "Run that emerge now? It shows its own plan and asks again before building."; then
        # emerge --ask reads its answer from stdin, which is the script itself
        # under `curl | bash`; point it at the terminal like confirm does.
        if ! "$SUDO" emerge --ask --noreplace --verbose "${want[@]}" < /dev/tty; then
            warn "emerge did not finish. The configs still deploy; re-run the command above when ready."
        fi
    else
        dim "skipped; the configs deploy either way"
    fi
}

install_packages() {
    local -a pkgs=("$@")
    local p
    [ "${#pkgs[@]}" -gt 0 ] || return 0

    if [ "$PM" = "emerge" ]; then
        install_packages_gentoo "${pkgs[@]}"
        return 0
    fi
    if [ -z "$PM" ]; then
        warn "unrecognised distro, install these yourself: ${pkgs[*]}"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        printf '    %swould run:%s %s\n' "$DIM" "$RESET" "$(pm_plan "${pkgs[@]}")"
        return 0
    fi

    if ! pm_install "${pkgs[@]}"; then
        warn "the batch failed, retrying one at a time so one bad name does not sink the rest"
        if [ "$PM" = "xbps" ]; then
            note "Void: if xbps itself is out of date, run '$SUDO xbps-install -Suy xbps' first."
        fi
        for p in "${pkgs[@]}"; do
            pm_install "$p" || warn "skipped, not found in your repos: $p"
        done
    fi
}

ensure_bootstrap_tools() {
    local missing=()
    command -v git >/dev/null 2>&1 || missing+=(git)
    command -v python3 >/dev/null 2>&1 || missing+=(python3)
    [ "${#missing[@]}" -eq 0 ] && return 0

    step "Installing bootstrap tools: ${missing[*]}"
    # These have the same name everywhere Silhouette claims to support.
    case "$PM" in
        dnf)    run "$SUDO" dnf install -y "${missing[@]}" ;;
        apk)    run "$SUDO" apk add --no-cache "${missing[@]}" ;;
        pacman) run "$SUDO" pacman -S --needed --noconfirm "${missing[@]}" ;;
        apt)    run "$SUDO" apt-get update && run "$SUDO" apt-get install -y "${missing[@]}" ;;
        zypper) run "$SUDO" zypper --non-interactive install "${missing[@]}" ;;
        xbps)   run "$SUDO" xbps-install -Sy "${missing[@]}" ;;
        emerge)
            # By now the source is already on disk (fetch_source checks for
            # git itself), so a missing git only matters for future updates.
            # Portage needs python, so python3 missing here means a broken
            # eselect python target rather than a missing package.
            local -a atoms=()
            has_item git "${missing[@]}" && atoms+=(dev-vcs/git)
            has_item python3 "${missing[@]}" && atoms+=(dev-lang/python)
            warn "Gentoo: not emerging these for you: ${atoms[*]}"
            note "$SUDO emerge --ask --noreplace ${atoms[*]}"
            has_item python3 "${missing[@]}" && note "if python is installed, check: eselect python list"
            return 0
            ;;
        *)      die "need ${missing[*]} and do not know how to install it on this distro" ;;
    esac
    command -v git >/dev/null 2>&1 || [ "$DRY_RUN" = "1" ] || die "git is still missing"
}

fetch_source() {
    if [ -n "$SRC_OVERRIDE" ]; then
        [ -d "$SRC_OVERRIDE" ] || die "--source $SRC_OVERRIDE is not a directory"
        SRC_DIR="$(cd -- "$SRC_OVERRIDE" && pwd)"
        [ -f "$SRC_DIR/hypr/hyprland.lua" ] || warn "$SRC_DIR does not look like a Silhouette checkout"
        note "using the checkout at $SRC_DIR"
        return 0
    fi

    # Standing inside a clone is the least surprising source of all: what you
    # are looking at is what gets deployed.
    if [ -f "$SCRIPT_DIR/hypr/hyprland.lua" ] && [ -d "$SCRIPT_DIR/quickshell" ]; then
        SRC_DIR="$SCRIPT_DIR"
        note "using the checkout this script lives in: $SRC_DIR"
        return 0
    fi

    # Everything past here clones or pulls, and this runs before the package
    # step, so git cannot be installed for you yet. A Gentoo stage3 is the
    # common case: it ships without git.
    if ! command -v git >/dev/null 2>&1; then
        case "$PM" in
            emerge) die "git is needed to fetch the repo: $SUDO emerge --ask dev-vcs/git (or pass --source PATH)" ;;
            *)      die "git is needed to fetch the repo; install it, or pass --source PATH" ;;
        esac
    fi

    if [ "$DRY_RUN" = "1" ] && [ ! -d "$DEFAULT_SRC" ]; then
        # A dry run still needs something to read. Clone into a temp dir and
        # delete it on exit, so the promise of "changes nothing" holds.
        TMP_SRC="$(mktemp -d)"
        note "dry run: fetching into a temporary directory"
        if ! git clone --depth 1 --branch "$REF" -- "$REPO_URL" "$TMP_SRC" >/dev/null 2>&1; then
            die "could not clone $REPO_URL ($REF)"
        fi
        SRC_DIR="$TMP_SRC"
        return 0
    fi

    if [ -d "$DEFAULT_SRC/.git" ]; then
        note "updating $DEFAULT_SRC"
        # fetch + fast-forward only: never discards edits in your own clone,
        # and fails loudly instead of half-applying a diverged branch.
        run git -C "$DEFAULT_SRC" fetch --depth 1 origin "$REF"
        if [ "$DRY_RUN" != "1" ]; then
            if ! git -C "$DEFAULT_SRC" merge --ff-only FETCH_HEAD >/dev/null 2>&1; then
                warn "$DEFAULT_SRC has local changes; deploying what is on disk as-is"
            fi
        fi
    elif [ -e "$DEFAULT_SRC" ] && [ -n "$(ls -A "$DEFAULT_SRC" 2>/dev/null)" ]; then
        die "$DEFAULT_SRC exists and is not a git checkout. Pass --dir or --source."
    else
        note "cloning $REPO_URL ($REF) into $DEFAULT_SRC"
        run mkdir -p "$(dirname "$DEFAULT_SRC")"
        run git clone --depth 1 --branch "$REF" -- "$REPO_URL" "$DEFAULT_SRC"
    fi
    SRC_DIR="$DEFAULT_SRC"
}

# Back up, then merge in. `cp -a src/. dst/` (rather than replacing the
# directory) keeps files that exist only on the target, which is the difference
# between an install and a wipe.
deploy_entry() {
    local entry="$1"
    local src="$SRC_DIR/$entry" dst="$CONFIG_DIR/$entry"

    [ -e "$src" ] || return 0
    # Running the installer from a checkout that is already ~/.config (the
    # most likely way to run it on this machine) makes every source equal to
    # its target. Copying a path onto itself fails, so say so and move on.
    if [ "$src" = "$dst" ]; then
        dim "source is the target: ~/.config/$entry"
        return 0
    fi

    if [ -e "$dst" ]; then
        if [ -d "$src" ] && diff -rq -- "$src" "$dst" >/dev/null 2>&1; then
            dim "already up to date: ~/.config/$entry"
            return 0
        fi
        run mkdir -p "$BACKUP_DIR/$(dirname "$entry")"
        run cp -a -- "$dst" "$BACKUP_DIR/$entry"
        note "backing up ~/.config/$entry"
    fi

    run mkdir -p "$CONFIG_DIR"
    # -f because some vendored files arrive read-only (a 444 flavour or plugin
    # file cannot be opened for writing, but it can be unlinked and rewritten).
    # Without it, a second install fails on the files the first one deployed.
    if [ -d "$src" ]; then
        run mkdir -p "$dst"
        if ! run cp -af -- "$src/." "$dst/"; then
            FAILED_ENTRIES+=("$entry")
            warn "could not copy all of ~/.config/$entry (see the errors above)"
            return 0
        fi
    else
        if ! run cp -af -- "$src" "$dst"; then
            FAILED_ENTRIES+=("$entry")
            warn "could not copy ~/.config/$entry"
            return 0
        fi
    fi
    note "deploying ~/.config/$entry"
}

rewrite_home_paths() {
    local rel f
    for rel in "${HOME_REWRITE[@]}"; do
        f="$CONFIG_DIR/$rel"
        [ -f "$f" ] || continue
        grep -q '/home/josh' "$f" 2>/dev/null || continue
        if [ "$DRY_RUN" = "1" ]; then
            printf '    %swould rewrite:%s /home/josh to %s in %s\n' "$DIM" "$RESET" "$HOME" "$rel"
            continue
        fi
        sed -i "s|/home/josh|$HOME|g" "$f"
        note "rewrote hardcoded paths in $rel"
    done
}

# Four files in scripts are not executable in the repo (a helper meant to
# be run by hand, and python engines the shell invokes as `python3 <file>`).
# Make the lot executable anyway: Hyprland's binds exec these by path, and a
# non-executable one is a bind that silently does nothing.
ensure_script_modes() {
    local dir="$CONFIG_DIR/scripts" f n=0
    [ -d "$dir" ] || return 0
    if [ "$DRY_RUN" = "1" ]; then
        printf '    %swould run:%s chmod +x %s/*.sh %s/*.py\n' "$DIM" "$RESET" "$dir" "$dir"
        return 0
    fi
    for f in "$dir"/*.sh "$dir"/*.py; do
        [ -f "$f" ] || continue
        [ -x "$f" ] && continue
        chmod +x "$f"
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] && note "made $n script(s) executable"
    return 0
}

write_portable_monitors() {
    cat > "$1" <<'EOF'
-- Written by install.sh: one monitor at its preferred mode, no hardcoded model
-- or scale, so the session comes up on whatever it is attached to.
-- The layout this repo shipped with is next to this file, as
-- monitors.lua.example. Swap it back in from Settings or by hand.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "", persistent = true })
end
EOF
}

install_portable_monitors() {
    [ "$KEEP_MONITORS" = "1" ] && return 0
    local dst="$CONFIG_DIR/hypr/modules/monitors.lua"
    local example="$CONFIG_DIR/hypr/modules/monitors.lua.example"

    [ -f "$dst" ] || return 0
    if [ -e "$example" ]; then
        dim "monitors.lua.example exists, leaving your layout alone"
        return 0
    fi
    run cp -a -- "$dst" "$example"
    if [ "$DRY_RUN" = "1" ]; then
        printf '    %swould write:%s the portable default to ~/.config/hypr/modules/monitors.lua\n' "$DIM" "$RESET"
    else
        write_portable_monitors "$dst"
    fi
    note "monitor layout: portable default written, original kept as monitors.lua.example"
}

# Small membership test for a plain array. The missing-tool list is tiny, so a
# loop is clearer than a pipeline and cannot be affected by SIGPIPE.
has_item() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# What the shell calls out to. Reported, never installed here: the packages are
# the ones above, and anything on this list that is still missing has a reason.
report_missing() {
    local -a missing=()
    local b
    for b in Hyprland hyprctl qs kitty cava playerctl cliphist wl-copy \
             notify-send jq curl brightnessctl nmcli bluetoothctl upower \
             wpctl python3 slurp; do
        command -v "$b" >/dev/null 2>&1 || missing+=("$b")
    done
    [ "${#missing[@]}" -eq 0 ] && { note "every tool the shell calls out to is present"; return 0; }

    step "Still missing"
    warn "${missing[*]}"
    # Quickshell gets its own line because it is the one dependency no distro
    # ships in its main repos, so it is the one people actually get stuck on.
    if has_item qs "${missing[@]}"; then
        printf '\n'
        case "$FAMILY" in
            fedora) note "quickshell: $SUDO dnf copr enable errornointernet/quickshell && $SUDO dnf install quickshell" ;;
            arch)   note "quickshell: $SUDO pacman -S quickshell (or quickshell-git from the AUR for the newest)" ;;
            void)   note "quickshell: $SUDO xbps-install -S quickshell" ;;
            gentoo) note "quickshell: in GURU: $SUDO eselect repository enable guru && $SUDO emerge --ask gui-apps/quickshell" ;;
            alpine) note "quickshell: not packaged for Alpine; build it from source: https://quickshell.org/docs/" ;;
            *)      note "quickshell is not in most distro repos, see https://quickshell.org/docs/ for your options" ;;
        esac
    fi
    # Void packages the whole desktop except the compositor itself.
    if has_item Hyprland "${missing[@]}" && [ "$FAMILY" = "void" ]; then
        printf '\n'
        note "Hyprland: not in Void's official repositories. The community repo is"
        note "  https://github.com/Makrennel/hyprland-void (xbps-src templates and binaries)"
    fi
    # Gentoo dropped Hyprland from the main tree; the old ::gentoo ebuild is
    # gone, not just masked, so `emerge hyprland` alone finds nothing.
    if has_item Hyprland "${missing[@]}" && [ "$FAMILY" = "gentoo" ]; then
        printf '\n'
        note "Hyprland: no longer in ::gentoo. It lives in the hyproverlay repository:"
        note "  $SUDO eselect repository enable hyproverlay && $SUDO emaint sync -r hyproverlay"
        note "  https://wiki.gentoo.org/wiki/Hyprland"
    fi
    # Alpine's stable repos stop short of these two; they live in edge/testing.
    if [ "$FAMILY" = "alpine" ]; then
        local -a alpine_testing=()
        has_item cava "${missing[@]}" && alpine_testing+=(cava)
        has_item cliphist "${missing[@]}" && alpine_testing+=(cliphist)
        if [ "${#alpine_testing[@]}" -gt 0 ]; then
            printf '\n'
            note "Alpine: ${alpine_testing[*]} are in edge/testing, not the stable repos."
            note "  https://dl-cdn.alpinelinux.org/alpine/edge/testing"
            note "Enable testing or build from source if you want those features."
        fi
    fi
    note "A missing tool degrades the one feature that uses it, not the session."
}

# Silhouette supports both systemd and OpenRC with first-class adaptation:
# power actions route through scripts/power.sh (systemctl vs loginctl/openrc-shutdown),
# user daemons (hypridle, hyprsunset, mpd) through scripts/user-service.sh,
# idle inhibition through scripts/inhibit.sh (systemd-inhibit vs elogind-inhibit),
# and session autostart through scripts/session-start.sh (D-Bus environment,
# pipewire audio stack on OpenRC, and hypridle).
report_init() {
    [ -d /run/systemd/system ] && return 0

    local init="a non-systemd init"
    if [ -d /run/openrc ] || command -v openrc >/dev/null 2>&1; then
        init="OpenRC"
    fi

    step "Init system: $init (first-class support enabled)"
    note "Silhouette automatically adapts: power actions route through elogind/loginctl,"
    note "inhibitors use elogind-inhibit, and daemons (hypridle, hyprsunset, mpd, pipewire)"
    note "are started and supervised cleanly via session-start.sh and user-service.sh."

    [ "$init" = "OpenRC" ] || return 0

    # service:runlevel. elogind provides the seat, logind API and loginctl
    # that Hyprland, the lockscreen and the polkit agent expect.
    local pair svc level
    local -a todo=()
    for pair in elogind:boot dbus:default NetworkManager:default bluetooth:default; do
        svc="${pair%%:*}" level="${pair##*:}"
        [ -e "/etc/init.d/$svc" ] || continue
        compgen -G "/etc/runlevels/*/$svc" >/dev/null && continue
        todo+=("$SUDO rc-update add $svc $level")
    done
    if [ ! -e /etc/init.d/elogind ] && [ ! -e /etc/init.d/seatd ]; then
        printf '\n'
        warn "neither elogind nor seatd is installed; Hyprland needs one for seat access"
        note "$SUDO emerge --ask sys-auth/elogind  (and USE=elogind globally)"
    fi
    if [ "${#todo[@]}" -gt 0 ]; then
        printf '\n'
        note "OpenRC services installed but not in any runlevel:"
        for pair in "${todo[@]}"; do
            dim "  $pair"
        done
    fi
}

main() {
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
    SRC_DIR=""
    TMP_SRC=""

    parse_args "$@"

    [ "$(id -u)" -eq 0 ] && die "run this as your normal user, not root: the configs would end up owned by root"
    [ -n "${HOME:-}" ] || die "HOME is not set"

    detect_distro
    if [ "$NO_DEPS" != "1" ]; then
        detect_privilege
        check_distro_repos
    fi
    STAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$STATE_DIR/backups/$STAMP"

    step "Silhouette installer $INSTALLER_VERSION"
    note "distro:  ${FAMILY}${PM:+ (via $PM)}"
    note "configs: $CONFIG_DIR"
    note "backups: $BACKUP_DIR"
    note "source:  ${SRC_OVERRIDE:-${DEFAULT_SRC}}"
    [ "$DRY_RUN" = "1" ] && note "${YELLOW}dry run: nothing will be written${RESET}"

    fetch_source
    if [ "$SRC_DIR" = "$CONFIG_DIR" ]; then
        note "this checkout is your live config: only the portable extras below will change"
    fi

    # One confirmation for the whole plan, before anything mutates.
    if [ "$DRY_RUN" != "1" ] && [ "$ASSUME_YES" != "1" ]; then
        say ""
        if [ "$NO_DEPS" = "1" ]; then
            say "About to deploy ${#CONFIG_ENTRIES[@]} config entries into $CONFIG_DIR."
        elif [ "$PM" = "emerge" ]; then
            say "About to check which Gentoo packages are missing (nothing is emerged without"
            say "asking again), then deploy ${#CONFIG_ENTRIES[@]} config entries into $CONFIG_DIR."
        else
            say "About to install packages with $SUDO, then deploy ${#CONFIG_ENTRIES[@]} config entries into $CONFIG_DIR."
        fi
        say "Anything already there is backed up to $BACKUP_DIR first."
        confirm "Continue?"
    fi

    if [ "$NO_DEPS" != "1" ]; then
        step "Dependencies"
        ensure_bootstrap_tools
        local -n core="CORE_${FAMILY}"
        if [ "$FULL" = "1" ]; then
            local -n extra="FULL_${FAMILY}"
            install_packages "${core[@]}" "${extra[@]}"
        else
            install_packages "${core[@]}"
        fi
    fi

    step "Deploying configs"
    local entry
    for entry in "${CONFIG_ENTRIES[@]}"; do
        deploy_entry "$entry"
    done
    rewrite_home_paths
    ensure_script_modes
    install_portable_monitors

    report_missing
    report_init

    step "Done"
    if [ "$DRY_RUN" = "1" ]; then
        note "That was a dry run. Nothing was installed. Drop --dry-run to do it for real."
    else
        note "Configs are in $CONFIG_DIR, scripts are executable as shipped."
        note "Reload an existing session with Super + R, or log out and start Hyprland."
        note "Roll back with: cp -a $BACKUP_DIR/. $CONFIG_DIR/"
        printf '\n'
        note "Optional tools this rice expects, install them if you want the feature:"
        for hint in "${OPTIONAL_HINTS[@]}"; do
            dim "  $hint"
        done
        if [ "$FAMILY" = "gentoo" ]; then
            dim "  Gentoo: both optional tools are available in GURU."
            dim "  $SUDO emerge --ask --noreplace app-eselect/eselect-repository"
            dim "  $SUDO eselect repository enable guru"
            dim "  $SUDO emaint sync -r guru"
            dim "  $SUDO emerge --ask --noreplace gui-apps/awww media-video/gpu-screen-recorder"
        fi
        printf '\n'
        note "rishot, the screenshot tool, lives in its own repo: grab it from there."
    fi

    if [ "${#FAILED_ENTRIES[@]}" -gt 0 ]; then
        printf '\n'
        warn "some entries did not copy cleanly: ${FAILED_ENTRIES[*]}"
        warn "your previous files for those are in $BACKUP_DIR. This is usually ownership, not the configs."
        exit 1
    fi
}

main "$@"
