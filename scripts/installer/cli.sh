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

Run control:
  -y, --yes           take the default answer to every question and skip the
                      final confirmation. It never opts into anything extra:
                      rishot needs --with-rishot.
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
               On Gentoo they are printed as an emerge command, never emerged unasked.

Exit status:
  0  done              every stage ok, skipped or warned
  1  stopped           a required stage failed or you said no; config rolled back
  2  bad usage         nothing ran
  3  done, with gaps   finished, but an optional stage (packages, rishot) failed
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

    # The stamp becomes a path component; keep it to what a stamp looks like.
    case "$ROLLBACK_STAMP" in
        */*|*..*) die "--rollback: $ROLLBACK_STAMP is not a backup name" ;;
    esac
}
