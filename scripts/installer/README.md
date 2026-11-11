# installer/

<!--toc:start-->
- [installer/](#installer)
  - [Layout](#layout)
  - [Stage order](#stage-order)
  - [The stage contract](#the-stage-contract)
  - [The journal](#the-journal)
  - [Exit status](#exit-status)
<!--toc:end-->

The modules behind `install.sh`. Both live at the top of the repo, which is
`~/.config`: `~/.config/install.sh` and `~/.config/installer/*.sh`. `install.sh` only decides the order of the
stages; everything else lives here.

**Goal:** deploy the dotfiles into `~/.config` so that either all of it lands
or `~/.config` is left exactly as it was.

## Layout

    lib/ui.sh        status tags, background tasks (progress_run), say/note/warn/err, run
    lib/util.sh      has_item, temp-path registry
    lib/prompt.sh    ask_yn, confirm, ask_choice (all read /dev/tty)
    lib/txn.sh       the undo journal: begin / protect / commit / rollback
    lib/stage.sh     the stage contract, runner, abort and the EXIT trap
    config.sh        constants, defaults, CONFIG_ENTRIES
    packages.sh      package names per distro family
    cli.sh           usage and option parsing
    distro.sh        distro, privilege (sudo/doas), package-manager calls
    gentoo.sh        Gentoo: overlays, keywords, atom checks, emerge (unattended)
    stages/          one file per phase; each defines stage_* functions

`lib/` knows nothing about Silhouette and could be reused. Modules declare
functions and data only; nothing runs until `main` in `install.sh` does.

## Stage order

    required  Preflight checks, Detect system, Fetch source, Review plan
    optional  Bootstrap tools, Enable package repos, Install packages, Verify hyprctl
                                                         (outside the transaction)
    required  Begin transaction
              Deploy configs, Rewrite home paths, Set script modes, Monitor layout
    required  Commit transaction
    optional  Install rishot, Install Flatpak apps (Sioyek, RetroArch), Install GRUB theme,
    Check runtime tools, Check init system, Check shell, Install extra assets

"Review plan" asks every question first, so the plan that is confirmed is the
plan that runs.

## The stage contract

    stage_example() {
        STAGE_DETAIL="3 files"       # optional, shown after the title
        return "$ST_OK"              # ST_OK | ST_FAIL | ST_SKIP | ST_WARN | ST_ABORT
    }

- `set -e` is **not** active inside a stage. Check every command that can fail.
- End with an explicit `return`; the last command's status is not a stage status.
- Print the reason with `err` before `return "$ST_FAIL"`. `die` is for bad usage only.
- Anything that writes under `~/.config` calls `txn_protect REL` first, and
  treats a non-zero return as "do not touch it".

`required` failure: offer a retry on a terminal, else roll back and exit 1.
`optional` failure: offer a retry on a terminal, else carry on; exit status 3.

To add a stage: write `stage_foo` in `stages/`, add the file to the `for`
list in `install.sh`, add a `stage required|optional "Title" stage_foo` line.

## The journal

`~/.local/state/silhouette-install/backups/<stamp>/journal`, tab separated,
paths relative to `~/.config`:

    ROOT    <abs path>     where the journal applies
    BACKUP  <rel>          existed; saved in files/<rel> before it was touched
    NEW     <rel>          did not exist; rollback removes it
    COMMIT                 the install finished
    ROLLED_BACK            a rollback finished

Replay is in reverse. Directories are restored by merging the backup back, so
files you added since are kept. No `COMMIT` and no `ROLLED_BACK` means the run
died; the next run warns, and `install.sh --rollback` can still undo it.

Not covered: packages and rishot (a package manager cannot be rolled back from
here). They run outside the transaction and never trigger a rollback.

## Exit status

    0 done   1 stopped, config rolled back   2 bad usage   3 done, an optional stage failed

## Background tasks and logs

A long command (package install, COPR enable, overlay sync, clone, Flatpak
install, emerge) runs as a quiet background-style task through `progress_run`:
one spinner line that updates in place, a live one-line status read from the
command's own log (`Installing: mpv`, `>>> Emerging (3 of 20) ...`), and no raw
package-manager output. The full log of each one is kept in
`~/.local/state/silhouette-install/logs/<stamp>/`; if a command fails, its last
lines and the log's path are shown.

Rules (in `lib/ui.sh`, `distro.sh`):

- Only wrap a **quiet** command. Never wrap a stage: stages print and ask.
- Never hide anything that may prompt. `priv_progress` / `pm_install_quiet` run a
  privileged command quietly only when `priv_ready` says no password can be
  asked (for sudo it asks right there, in the foreground, and caches it); with
  doas or su the command runs plainly, output visible.
- Off a terminal there is no animation and commands keep their output.
- A loop of small commands shares one log with `PROGRESS_LOGNAME=name`.

## Third-party repositories

- **Fedora** enables COPRs before packages: `lionheartp/Hyprland` (hyprland-git),
  `errornointernet/quickshell`, and, only with `--full`, `lihaohong/yazi`.
- The core package set includes the XDG desktop portal, GTK chooser backend,
  Hyprland portal backend, and Papirus icon theme. The post-install asset stage
  offers optional user-local fonts; SF Pro is linked for manual installation
  because it is Apple-licensed.
- **Gentoo** enables the `hyproverlay` (hosted on Codeberg) and `guru` overlays and
  accepts their keywords; every atom is checked with `portageq` first.
- **GRUB theme** (Evangelion) is pinned to a release tag (`EVA_REF`), runs only
  where GRUB 2 exists, saves `/etc/default/grub` first, and is applied with
  `install.sh --no-apply` then `eva set`, so you are asked once. It is outside
  `--rollback`; upstream's own undo is `sudo eva uninstall`.
