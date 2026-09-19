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
CORE_fedora=(hyprland kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify slurp NetworkManager bluez upower
    wireplumber xdg-utils ffmpeg ImageMagick python3-dbus)
CORE_arch=(hyprland kitty jq curl python brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify slurp networkmanager bluez upower
    wireplumber xdg-utils ffmpeg imagemagick python-dbus)
CORE_debian=(hyprland kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify-bin slurp network-manager bluez upower
    wireplumber xdg-utils ffmpeg imagemagick python3-dbus)
CORE_suse=(hyprland kitty jq curl python3 brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify-tools slurp NetworkManager bluez upower
    wireplumber xdg-utils ffmpeg ImageMagick python3-dbus-python)
CORE_gentoo=(hyprland kitty jq curl python brightnessctl ddcutil cava playerctl
    cliphist wl-clipboard libnotify slurp networkmanager bluez upower
    wireplumber xdg-utils ffmpeg imagemagick dbus-python)
# Nothing to guess from. The generic names are listed so the report is concrete
# and the user can map them to whatever their package manager calls them.
CORE_unknown=(hyprland quickshell kitty jq curl python3 brightnessctl ddcutil cava
    playerctl cliphist wl-clipboard libnotify slurp networkmanager bluez upower
    wireplumber xdg-utils ffmpeg imagemagick)

# --full: the daily apps on top of the core, plus yazi's helpers so the file
# manager previews instead of erroring on every file type.
FULL_fedora=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip fd-find ripgrep fzf zoxide bat chafa)
FULL_arch=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf zoxide bat chafa)
FULL_debian=(nautilus firefox-esr yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip-full fd-find ripgrep fzf zoxide bat chafa)
FULL_suse=(nautilus MozillaFirefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-tools p7zip fd ripgrep fzf zoxide bat chafa)
FULL_gentoo=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf zoxide bat chafa)
FULL_unknown=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf zoxide bat chafa)

# Never installed automatically: these need kernel modules, driver quirk
# handling or hardware nobody else has. Reported at the end instead.
OPTIONAL_HINTS=(
    "awww: the wallpaper daemon the scripts drive (Arch: awww / awww-git, otherwise build from source)"
    "gpu-screen-recorder: hardware-encoded screen recording (flatpak works too)"
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

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
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
  dependencies through your distro's package manager (sudo)
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
        *arch*)                   FAMILY="arch" ;;
        *debian*|*ubuntu*)        FAMILY="debian" ;;
        *suse*|*opensuse*)        FAMILY="suse" ;;
        *gentoo*)                 FAMILY="gentoo" ;;
        *)                        FAMILY="unknown" ;;
    esac

    case "$FAMILY" in
        fedora) PM="dnf" ;;
        arch)   PM="pacman" ;;
        debian) PM="apt" ;;
        suse)   PM="zypper" ;;
        gentoo) PM="emerge" ;;
        *)      PM="" ;;
    esac
}

# One package-manager invocation. Kept separate from install_packages so the
# batch can be retried per package when a single name is wrong for a release.
pm_install() {
    case "$PM" in
        dnf)    sudo dnf install -y "$@" ;;
        pacman) sudo pacman -S --needed --noconfirm "$@" ;;
        apt)    sudo apt-get install -y "$@" ;;
        zypper) sudo zypper --non-interactive install "$@" ;;
        *)      return 1 ;;
    esac
}

# The same invocation as a string, so --dry-run shows the real command instead
# of the name of the function that would have run it.
pm_plan() {
    case "$PM" in
        dnf)    echo "sudo dnf install -y $*" ;;
        pacman) echo "sudo pacman -S --needed --noconfirm $*" ;;
        apt)    echo "sudo apt-get install -y $*" ;;
        zypper) echo "sudo zypper --non-interactive install $*" ;;
        *)      echo "(no package manager detected) $*" ;;
    esac
}

install_packages() {
    local -a pkgs=("$@")
    local p
    [ "${#pkgs[@]}" -gt 0 ] || return 0

    if [ "$PM" = "emerge" ]; then
        note "Gentoo: these are yours to emerge, flags and USE masks included:"
        note "  ${pkgs[*]}"
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
        dnf)    run sudo dnf install -y "${missing[@]}" ;;
        pacman) run sudo pacman -S --needed --noconfirm "${missing[@]}" ;;
        apt)    run sudo apt-get update && run sudo apt-get install -y "${missing[@]}" ;;
        zypper) run sudo zypper --non-interactive install "${missing[@]}" ;;
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

# Four files in hypr/scripts are not executable in the repo (a helper meant to
# be run by hand, and python engines the shell invokes as `python3 <file>`).
# Make the lot executable anyway: Hyprland's binds exec these by path, and a
# non-executable one is a bind that silently does nothing.
ensure_script_modes() {
    local dir="$CONFIG_DIR/hypr/scripts" f n=0
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
    if printf '%s\n' "${missing[@]}" | grep -qx qs; then
        printf '\n'
        case "$FAMILY" in
            fedora) note "quickshell: sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell" ;;
            arch)   note "quickshell: sudo pacman -S quickshell (or quickshell-git from the AUR for the newest)" ;;
            *)      note "quickshell is not in most distro repos, see https://quickshell.org/docs/ for your options" ;;
        esac
    fi
    note "A missing tool degrades the one feature that uses it, not the session."
}

main() {
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
    SRC_DIR=""
    TMP_SRC=""

    parse_args "$@"

    [ "$(id -u)" -eq 0 ] && die "run this as your normal user, not root: the configs would end up owned by root"
    [ -n "${HOME:-}" ] || die "HOME is not set"

    detect_distro
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
        else
            say "About to install packages with sudo, then deploy ${#CONFIG_ENTRIES[@]} config entries into $CONFIG_DIR."
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

    step "Done"
    if [ "$DRY_RUN" = "1" ]; then
        note "That was a dry run. Nothing was installed. Drop --dry-run to do it for real."
    else
        note "Configs are in $CONFIG_DIR, hypr/scripts are executable as shipped."
        note "Reload an existing session with Super + R, or log out and start Hyprland."
        note "Roll back with: cp -a $BACKUP_DIR/. $CONFIG_DIR/"
        printf '\n'
        note "Optional tools this rice expects, install them if you want the feature:"
        for hint in "${OPTIONAL_HINTS[@]}"; do
            dim "  $hint"
        done
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
