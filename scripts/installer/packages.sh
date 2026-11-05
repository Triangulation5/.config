# shellcheck shell=bash
# packages.sh: package names per distro family. Declares data; does nothing
# when sourced. Names differ per family because they genuinely differ
# (libnotify vs libnotify-bin, python3-dbus vs python-dbus). Selected at
# run time through the CORE_${FAMILY} / FULL_${FAMILY} namerefs in
# stages/deps.sh, so a new family is one new pair of arrays here.
#
# These are plain arrays read through namerefs, which shellcheck cannot follow.
# shellcheck disable=SC2034

# Core packages: what the session and the shell actually call out to. Names are
# per distro family because they genuinely differ (libnotify vs libnotify-bin,
# python3-dbus vs python-dbus).
# shellcheck disable=SC2034 # selected through the CORE_${FAMILY} nameref
CORE_fedora=(hyprland-git quickshell kitty jq curl python3 brightnessctl ddcutil cava
    playerctl cliphist wl-clipboard libnotify slurp NetworkManager neovim bluez upower
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
# Gentoo takes full category/package atoms, and several are not in ::gentoo:
# gui-wm/hyprland is in hyproverlay; gui-apps/quickshell, app-misc/brightnessctl,
# app-misc/cliphist and (below) app-misc/yazi are in GURU. gentoo.sh enables both
# overlays and accepts their keywords before anything is emerged, and checks each
# atom with portageq, so a name that has moved is reported instead of failing the
# whole emerge. Atoms checked against packages.gentoo.org and the overlays, 2026-11.
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
    poppler-utils p7zip fd-find ripgrep fzf chafa)
# shellcheck disable=SC2034
FULL_arch=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf chafa)
# shellcheck disable=SC2034
FULL_debian=(nautilus firefox-esr yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip-full fd-find ripgrep fzf chafa)
# shellcheck disable=SC2034
FULL_suse=(nautilus MozillaFirefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-tools p7zip fd ripgrep fzf chafa)
# yazi is GURU's; the rest are ::gentoo. poppler's `utils` USE flag (on by
# default) is what provides pdftoppm for yazi's PDF previews.
# Two deliberate choices on Gentoo:
#   app-arch/7zip     app-arch/p7zip was last-rited and removed (2026-08-15); 7zip
#                     is its replacement and provides the 7zz yazi looks for.
#   www-client/firefox-bin
#                     the source build compiles Rust and LLVM for hours and wants
#                     many GB of RAM; the binary package is the dependable choice.
# shellcheck disable=SC2034
FULL_gentoo=(gnome-base/nautilus www-client/firefox-bin app-misc/yazi
    media-sound/mpd media-sound/ncmpcpp sys-process/btop
    media-video/ffmpegthumbnailer app-text/poppler app-arch/7zip sys-apps/fd
    sys-apps/ripgrep app-shells/fzf
    media-gfx/chafa)
# Alpine does not package p7zip; the upstream 7zip package provides both 7z
# and 7zz, which is what yazi looks for.
# shellcheck disable=SC2034
FULL_alpine=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils 7zip fd ripgrep fzf chafa)
# shellcheck disable=SC2034
FULL_void=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer
    poppler-utils p7zip fd ripgrep fzf chafa)
# shellcheck disable=SC2034
FULL_unknown=(nautilus firefox yazi mpd ncmpcpp btop ffmpegthumbnailer poppler
    p7zip fd ripgrep fzf chafa)


# COPR projects enabled before the package step (Fedora only; dnf copr enable).
#   lionheartp/Hyprland     hyprland-git, which provides hyprctl, plus the hypr* libraries
#   errornointernet/quickshell   quickshell, which Fedora does not ship
# hyprland-git conflicts with the plain hyprland package: if that is installed
# from another repo, dnf refuses and the package is reported as skipped.
COPR_fedora=(lionheartp/Hyprland errornointernet/quickshell)

# The package that carries hyprctl. hyprctl is not packaged on its own anywhere:
# it ships inside the compositor package. Void has none (see report_missing).
declare -A HYPRLAND_PKG=(
    [fedora]=hyprland-git [arch]=hyprland [debian]=hyprland [suse]=hyprland
    [alpine]=hyprland [gentoo]=gui-wm/hyprland
)
