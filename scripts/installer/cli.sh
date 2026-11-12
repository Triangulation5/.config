# shellcheck shell=bash
# cli.sh: the command line. The only file that knows the option names.

usage() {
    cat <<EOF
${BOLD}Silhouette installer ${INSTALLER_VERSION}${RESET}

Deploys the dotfiles into ~/.config as one transaction: either all of it lands,
or ~/.config is put back the way it was.

Usage:
  ./install.sh [options]
  curl -fsSL <repo>/install.sh | bash -s -- [options]
  ./install.sh --rollback [STAMP]

Questions (asked on a terminal; a flag answers the question in advance):
      --full / --core            also install the daily apps, or core packages only
      --keep-monitors            deploy the repo's monitor layout as it is
      --portable-monitors        use one preferred-mode output instead (the default)
      --with-rishot / --no-rishot
                                 install the rishot screenshot tool by running
                                 its own installer ($RISHOT_URL)
      --with-retroarch / --no-retroarch
                                 install RetroArch as a user Flatpak
                                 ($RETROARCH_ID from Flathub)
      --terminal kitty|st
                      kitty is the default; st also builds the custom Simple
                      Terminal from github.com/triangulation5/st
      --with-sioyek / --no-sioyek
                                 install Sioyek as a user Flatpak (installed by default)
                                 ($SIOYEK_ID from Flathub)
      --with-grub-theme / --no-grub-theme
                                 install Evangelion GRUB theme
                                 (clones to ~/Projects/Evangelion, sets seele theme)
      --grub-profile 720p|1080p|1440p
                                 display profile for Evangelion GRUB theme (default: 1080p)
      --with-pi-harness / --no-pi-harness
                                 install Pi coding agent harness, extensions, and skills
      --with-ollama / --no-ollama
                                 install Ollama and select local LLM models
      --shell bash|zsh|keep      install bash or zsh, or keep the shell you have.
                                 Switching your login shell is never done for you:
                                 the steps are printed at the end.

Run control:
  -y, --yes           take the default answer to every question and skip the
                      final confirmation. It never opts into anything extra:
                      rishot needs --with-rishot, RetroArch --with-retroarch,
                      GRUB theme needs --with-grub-theme, Pi harness needs --with-pi-harness,
                      Ollama needs --with-ollama, Sioyek is installed
                      unless --no-sioyek, and your shell is kept unless you pass --shell.
      --quickstart    same as --yes
      --no-deps       skip the package step, only deploy the configs
      --dry-run       walk the whole flow and change nothing

Source:
      --dir PATH      clone and deploy from PATH (default: $DEFAULT_SRC)
      --source PATH   deploy from a clone you already have, no fetching
      --ref REF       branch or tag to fetch (default: $REF)

Undo:
      --rollback [STAMP]
                      undo an install from its journal: the latest one, or the
                      one named STAMP (a directory under $STATE_DIR/backups)

  -h, --help          show this help and exit
      --version       show the version and exit

What it will touch:
  configs      $CONFIG_DIR
  journal and backups
               $STATE_DIR/backups/<timestamp>
  packages     through your distro's package manager (sudo or doas). Packages are
               outside the transaction: a rollback leaves them installed.
               On Gentoo this enables the guru and hyproverlay overlays, accepts their
               keywords, and emerges everything: it compiles, and can take hours.

Exit status:
  0  done              every stage ok, skipped or warned
  1  stopped           a required stage failed or you said no; config rolled back
  2  bad usage         nothing ran
  3  done, with gaps   finished, but an optional stage (packages, rishot, Flatpak apps, GRUB theme) failed
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)            usage; exit 0 ;;
            --version)            say "$INSTALLER_VERSION"; exit 0 ;;
            -y|--yes|--quickstart) ASSUME_YES=1 ;;
            --full)               FULL=1 ;;
            --core)               FULL=0 ;;
            --no-deps)            NO_DEPS=1 ;;
            --dry-run)            DRY_RUN=1 ;;
            --keep-monitors)      KEEP_MONITORS=1 ;;
            --portable-monitors)  KEEP_MONITORS=0 ;;
            --with-rishot)        WANT_RISHOT=1 ;;
            --no-rishot)          WANT_RISHOT=0 ;;
            --with-retroarch)     WANT_RETROARCH=1 ;;
            --no-retroarch)       WANT_RETROARCH=0 ;;
            --with-sioyek)        WANT_SIOYEK=1 ;;
            --no-sioyek)          WANT_SIOYEK=0 ;;
            --with-grub-theme|--with-eva)  WANT_GRUB_THEME=1 ;;
            --no-grub-theme|--no-eva)      WANT_GRUB_THEME=0 ;;
            --with-pi-harness)             WANT_PI_HARNESS=1 ;;
            --no-pi-harness)               WANT_PI_HARNESS=0 ;;
            --terminal)                    TERMINAL_CHOICE="${2:?--terminal needs kitty or st}"; shift
                case "$TERMINAL_CHOICE" in kitty|st) ;; *) die "--terminal: $TERMINAL_CHOICE is not kitty or st" ;; esac ;;
            --with-ollama)                 WANT_OLLAMA=1 ;;
            --no-ollama)                   WANT_OLLAMA=0 ;;
            --grub-profile|--eva-profile)
                GRUB_PROFILE="${2:?--grub-profile needs 720p, 1080p or 1440p}"
                shift
                case "$GRUB_PROFILE" in
                    720p|1080p|1440p) ;;
                    *) die "--grub-profile: $GRUB_PROFILE is not 720p, 1080p or 1440p" ;;
                esac
                ;;
            --shell)              SHELL_CHOICE="${2:?--shell needs bash, zsh or keep}"; shift ;;
            --dir)                DEFAULT_SRC="${2:?--dir needs a path}"; shift ;;
            --source)             SRC_OVERRIDE="${2:?--source needs a path}"; shift ;;
            --ref)                REF="${2:?--ref needs a branch or tag}"; shift ;;
            --rollback)
                MODE="rollback"
                if [ "$#" -gt 1 ] && [ "${2#-}" = "$2" ]; then
                    ROLLBACK_STAMP="$2"
                    shift
                fi
                ;;
            *)                    die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done

    case "$SHELL_CHOICE" in
        ''|bash|zsh|keep) ;;
        *) die "--shell: $SHELL_CHOICE is not bash, zsh or keep" ;;
    esac

    # The stamp becomes a path component; keep it to what a stamp looks like.
    case "$ROLLBACK_STAMP" in
        */*|*..*) die "--rollback: $ROLLBACK_STAMP is not a backup name" ;;
    esac
}
