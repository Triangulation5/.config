# scripts/installer

The modules behind `install.sh`. `install.sh` only decides the order of the
stages; everything else lives here.

**Goal:** deploy the dotfiles into `~/.config` so that either all of it lands
or `~/.config` is left exactly as it was.

## Layout

    lib/ui.sh        status tags ([   Ok   ] / [ Failed ] ...), say/note/warn/err, run
    lib/util.sh      has_item, temp-path registry
    lib/prompt.sh    ask_yn, confirm, ask_choice (all read /dev/tty)
    lib/txn.sh       the undo journal: begin / protect / commit / rollback
    lib/stage.sh     the stage contract, runner, abort and the EXIT trap
    config.sh        constants, defaults, CONFIG_ENTRIES
    packages.sh      package names per distro family
    cli.sh           usage and option parsing
    distro.sh        distro, privilege (sudo/doas), package-manager calls
    gentoo.sh        Gentoo's print-the-plan flow
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
    optional  Install rishot, Check runtime tools, Check init system

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
