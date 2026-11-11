# shellcheck shell=bash
# distro.sh: what system is this, and how do we talk to its package manager.
# Functions only; the stages in stages/preflight.sh and stages/deps.sh call them.

# Sets FAMILY and PM.
detect_distro() {
    local id="" like="" osr=""
    if [ -r /etc/os-release ]; then
        # Read in a subshell: os-release defines NAME, VERSION and friends, and
        # none of them should leak into this script's variables.
        osr="$(. /etc/os-release >/dev/null 2>&1; printf '%s|%s' "${ID:-}" "${ID_LIKE:-}")" || osr="|"
        id="${osr%%|*}"
        like="${osr#*|}"
    fi

    case " $id $like " in
        *fedora*|*rhel*|*centos*) FAMILY="fedora" ;;
        *alpine*)                 FAMILY="alpine" ;;
        *artix*)                  FAMILY="artix" ;;
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
# Returns non-zero only when a real run cannot go on.
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
        err "need sudo or doas to install packages (or re-run with --no-deps)"
        return 1
    fi
    return 0
}

# Run a command with elevated privileges. Uses $SUDO if available,
# or su -c on Gentoo/minimal installs without sudo or doas.
priv_run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        would_do run "$SUDO $*"
        return 0
    fi
    if [ "${HAVE_PRIV:-1}" = "1" ] || command -v "$SUDO" >/dev/null 2>&1; then
        "$SUDO" "$@"
        return $?
    fi
    su -c "$(printf '%q ' "$@")"
}

# Alpine's archive is split: main has the base, community has hyprland, kitty,
# wireplumber and most of the desktop stack. A minimal install can enable only
# main, which would make the whole batch fail for a reason the user can fix in
# one line, so name it up front instead of after the retries.
# Returns 1 when it had something to say.
check_distro_repos() {
    [ "$FAMILY" = "alpine" ] || return 0
    [ -r /etc/apk/repositories ] || return 0
    if ! grep -Eq '^[^#]*community/?[[:space:]]*$' /etc/apk/repositories; then
        warn "Alpine: community is not enabled in /etc/apk/repositories; most desktop packages live there."
        note "Enable it with 'setup-apkrepos', or add .../alpine/<release>/community."
        return 1
    fi
    return 0
}

# One package-manager invocation. Kept separate from the stage so the batch can
# be retried per package when a single name is wrong for a release.
pm_install() {
    case "$PM" in
        dnf)    "$SUDO" dnf install -y "$@" ;;
        apk)    "$SUDO" apk add --no-cache "$@" ;;
        pacman) "$SUDO" pacman -S --needed --noconfirm "$@" ;;
        # Non-interactive and keeping existing config files: this can run behind a
        # quiet task, where a debconf question would look exactly like a hang.
        apt)    "$SUDO" env DEBIAN_FRONTEND=noninteractive \
                    apt-get install -y -o Dpkg::Options::=--force-confold "$@" ;;
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

# `dnf copr` is a plugin: dnf-plugins-core on dnf4, dnf5-plugins on dnf5.
# Returns 0 when `dnf copr` works afterwards.
dnf_copr_ready() {
    dnf copr --help >/dev/null 2>&1 && return 0
    priv_progress "Installing dnf-plugins-core" dnf install -y dnf-plugins-core || true
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    dnf copr --help >/dev/null 2>&1 && return 0
    priv_progress "Installing dnf5-plugins" dnf install -y dnf5-plugins || true
    dnf copr --help >/dev/null 2>&1
}

# Can root be reached at all? A real run with no sudo or doas needs a terminal
# for su's password prompt. Used by every stage that runs a privileged command.
priv_check() {
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    [ "${HAVE_PRIV:-1}" = "1" ] && return 0
    if tty_available; then
        note "no sudo or doas here: root's password will be asked (su)"
        return 0
    fi
    err "no sudo or doas, and no terminal to ask root's password on. Install one, or run on a terminal."
    return 1
}

# Will a privileged command run WITHOUT asking for a password? If a prompt is
# still possible it must not be hidden behind a spinner, so this answers that.
# For sudo it asks for the password right here, in the foreground, which also
# caches it for the command that follows. doas and su cannot be primed.
priv_ready() {
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    [ "${HAVE_PRIV:-1}" = "1" ] || return 1
    case "$SUDO" in
        sudo) sudo -v ;;
        doas) doas -n true 2>/dev/null ;;
        *)    return 1 ;;
    esac
}

# priv_progress LABEL COMMAND...   a privileged, quiet command: as a background
# task (spinner, live status, log on disk) when no prompt can appear, plainly
# (output visible) when one might.
priv_progress() {
    local label="$1"
    shift
    if [ "${DRY_RUN:-0}" = "1" ]; then
        priv_run "$@"
        return
    fi
    if priv_ready; then
        progress_run "$label" priv_run "$@"
    else
        priv_run "$@"
    fi
}

# pm_install_quiet LABEL PACKAGE...   pm_install as a background task, on the same
# rule: hidden only when it cannot ask for a password.
pm_install_quiet() {
    local label="$1"
    shift
    if priv_ready; then
        progress_run "$label" pm_install "$@"
    else
        pm_install "$@"
    fi
}
