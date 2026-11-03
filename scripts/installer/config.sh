# shellcheck shell=bash
# config.sh: every constant and default in one place. Declares data; does
# nothing when sourced. (REPO_URL, REF and DEFAULT_SRC live in install.sh,
# because the bootstrap needs them before this file can be loaded.)

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
# Deliberately `silhouette-install`, not `silhouette`: the shell owns
# ~/.local/state/silhouette itself (its flags, its calendar, its own backups),
# and two sets of backups sharing one directory would each read the other's
# files as their own.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/silhouette-install"

# The screenshot tool lives in its own repo and ships its own installer.
# SILHOUETTE_RISHOT_URL exists so the stage can be tested without the network.
RISHOT_URL="${SILHOUETTE_RISHOT_URL:-https://raw.githubusercontent.com/Gakuseei/rishot/main/install.sh}"

# Top-level entries in the repo that belong in ~/.config. install.sh itself,
# the README and .gitignore are deliberately not here: they are repo furniture,
# not config. Neither are the machine-local ones .gitignore keeps out of the
# repo - rygel.conf and QtProject.conf belong to the packages that own them on
# each machine, so there is nothing here to deploy. mpd is here for its
# configuration alone: the library database, the log, the pid and the session
# state are ignored beside it, so a clone carries the conf and nothing else.
# Keep this in sync when a new top-level config lands.
#
# NOTE: `scripts` is not listed, yet stage_script_modes expects
# ~/.config/scripts. If scripts/ is meant to be deployed, add it here, and keep
# scripts/installer out of the copy (it is the installer, not config).
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

# Never installed automatically: these need kernel modules, driver quirk
# handling or hardware nobody else has. Reported at the end instead.
OPTIONAL_HINTS=(
    "awww: the wallpaper daemon the scripts drive (Arch: awww / awww-git, Gentoo: gui-apps/awww in GURU, otherwise build from source)"
    "gpu-screen-recorder: hardware-encoded screen recording (Gentoo: media-video/gpu-screen-recorder in GURU, Flatpak also available)"
    "howdy: face unlock on the lockscreen, needs a camera and a PAM entry"
    "zenity or kdialog: the native folder picker for the wallpaper strip"
)

# ---- run-time switches: set by cli.sh, finished by stage_plan ----------------
MODE="install"          # install | rollback
ROLLBACK_STAMP=""       # which install --rollback undoes; empty = the latest
DRY_RUN=0
ASSUME_YES=0
NO_DEPS=0
SRC_OVERRIDE=""
# Three questions the installer can ask. Empty means "not decided yet": ask if
# there is a terminal, otherwise take the default (core only, portable
# monitors, no rishot). A flag answers the question in advance.
FULL=""
KEEP_MONITORS=""
WANT_RISHOT=""

# ---- filled in by the stages --------------------------------------------------
FAMILY=""               # stage_detect
PM=""                   # stage_detect
SUDO="sudo"             # stage_detect: sudo or doas, kept as a plain command
HAVE_PRIV=1             # 0 when neither exists (Gentoo and --dry-run only)
SRC_DIR=""              # stage_source
FAILED_ENTRIES=()       # stage_deploy_configs
