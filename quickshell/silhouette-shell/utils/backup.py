#!/usr/bin/env python3
"""
backup.py — snapshot, list, restore and remove backups of the shell's own
config, for the settings app's Backups page.

A backup is the two things this shell owns:

  ~/.config/quickshell/silhouette-shell   the shell itself: every surface, the
                                          settings app and these helpers
  ~/.local/state/silhouette/flags.json       the flags every page edits
  ~/.local/state/silhouette/events.json      the calendar events service holds
  ~/.local/state/silhouette-wallpaper        the chosen wallpaper's path

It is deliberately *not* a backup of the Hyprland config the shell is built
around: those files live in `~/.config/hypr`, this script is not their owner, and
the settings app already writes each of them through its own service.

Archives land in `~/.local/state/silhouette/backups/`, one timestamped tarball each,
named `silhouette-YYYY-MM-DDTHH-MM-SS.tar.gz` so the directory sorts
oldest-first. Inside, the members are fixed names — `silhouette-shell/`,
`flags.json`, `events.json`, `silhouette-wallpaper` — and not the paths they came
from, so an archive restores into whatever those paths are on the machine
reading it.

Contract: one JSON object on stdout per run, the shape `scripts/silhouette-update.py`
already answers with (`status`, and `error` when it is not "ok").

  backup.py create         -> { status, name, path, bytes, files, created }
  backup.py list           -> { status, backups: [ { name, path, bytes, created } ] }
  backup.py restore NAME   -> { status, name, files, flags }
  backup.py remove NAME    -> { status, name }

Nothing here escalates, and nothing is written outside the backup directory and
the paths above. A restore overwrites what the archive holds and adds back what
is missing, but never deletes a file that arrived after the backup was taken —
restoring an old snapshot cannot take a newer file with it.

Env knobs, each also a flag so an audit can run against a scratch tree:
  SILHOUETTE_SHELL_DIR    the shell tree       (--shell)
  SILHOUETTE_BACKUP_DIR   where archives land  (--dir)
  SILHOUETTE_STATE_DIR    the shell's state    (--state)
"""

import argparse
import datetime
import json
import os
import shutil
import sys
import tarfile
import tempfile
import time

HOME = os.path.expanduser("~")

# Member names inside the archive. Fixed rather than derived from the paths on
# disk: a backup records *what* the shell's config is, not where it happened to
# live on the machine that made it.
SHELL_MEMBER = "silhouette-shell"
FLAG_MEMBER = "flags.json"
EVENT_MEMBER = "events.json"
WALLPAPER_MEMBER = "silhouette-wallpaper"
# What the wallpaper member was called before the paths were renamed.
# `inside()` has to accept it so archives written back then still restore.
LEGACY_WALLPAPER_MEMBER = "ricelin-wallpaper"
STATE_MEMBERS = (FLAG_MEMBER, EVENT_MEMBER, WALLPAPER_MEMBER, LEGACY_WALLPAPER_MEMBER)

PREFIX = "silhouette-"
SUFFIX = ".tar.gz"

# Left out of both directions: byte-code caches are regenerated on the next run,
# keyed to the interpreter that wrote them, and would only make the archive look
# bigger than the config is.
SKIP_DIRS = {"__pycache__"}
SKIP_SUFFIXES = (".pyc", ".pyo")


def emit(payload):
    """Print one JSON object and return a success code."""
    print(json.dumps(payload))
    return 0


def error(message):
    """Print one JSON object carrying a line to show, and return a failure code."""
    print(json.dumps({"status": "error", "error": message}))
    return 1


def state_dir():
    return os.environ.get("SILHOUETTE_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"),
        "silhouette",
    )


def defaults():
    """Where the shell and its state are, unless the caller says otherwise."""
    state = state_dir()
    return {
        "shell": os.environ.get("SILHOUETTE_SHELL_DIR")
        or os.path.join(HOME, ".config", "quickshell", "silhouette-shell"),
        "state": state,
        "dir": os.environ.get("SILHOUETTE_BACKUP_DIR")
        or os.path.join(state, "backups"),
    }


def state_files(state):
    """Every state file the shell owns: its member name, and where it lives.

    The state is not quite one directory — the flags and the calendar's events
    sit in the state directory itself, and the chosen wallpaper's path beside it
    in `silhouette-wallpaper` — so the two halves of this mapping are kept together
    here rather than assumed at each end.
    """
    beside = os.path.dirname(state)
    return [
        (FLAG_MEMBER, os.path.join(state, FLAG_MEMBER)),
        (EVENT_MEMBER, os.path.join(state, EVENT_MEMBER)),
        (WALLPAPER_MEMBER, os.path.join(beside, WALLPAPER_MEMBER)),
    ]


def keep(info):
    """tarfile filter: drop the caches, keep everything else."""
    name = os.path.basename(info.name)
    if info.isdir() and name in SKIP_DIRS:
        return None
    if name.endswith(SKIP_SUFFIXES):
        return None
    return info


def create(args):
    """Write one archive holding the shell and the state files that exist."""
    shell = os.path.abspath(args.shell)
    state = os.path.abspath(args.state)
    if not os.path.isdir(shell):
        return error("%s is not a directory" % shell)

    name = PREFIX + datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S") + SUFFIX
    path = os.path.join(args.dir, name)
    partial = path + ".part"

    try:
        os.makedirs(args.dir, exist_ok=True)
        with tarfile.open(partial, "w:gz") as tar:
            tar.add(shell, arcname=SHELL_MEMBER, filter=keep)
            for member, source in state_files(state):
                if os.path.isfile(source):
                    tar.add(source, arcname=member)
            files = sum(1 for entry in tar.getmembers() if entry.isfile())
        # The archive only becomes visible under its final name once it is whole:
        # a run interrupted half-way leaves nothing for the page to list.
        os.replace(partial, path)
    except OSError as problem:
        discard(partial)
        return error("Could not write %s: %s" % (path, problem))

    return emit({
        "status": "ok",
        "name": name,
        "path": path,
        "bytes": os.path.getsize(path),
        "files": files,
        "created": int(time.time()),
    })


def backups(directory):
    """Every archive in `directory`, newest first."""
    found = []
    if os.path.isdir(directory):
        for name in os.listdir(directory):
            if not name.startswith(PREFIX) or not name.endswith(SUFFIX):
                continue
            entry = resolve(directory, name)
            if entry is None:
                continue
            stat = os.stat(entry)
            found.append({"name": name, "path": entry,
                          "bytes": stat.st_size, "created": int(stat.st_mtime)})
    found.sort(key=lambda entry: entry["created"], reverse=True)
    return found


def resolve(directory, name):
    """The archive `name` in `directory`, or None when it is not one of ours.

    Only a bare file name of an archive this script wrote is accepted, so a name
    arriving from the page can never name a file outside the backup directory.
    """
    if os.path.basename(name) != name:
        return None
    if not name.startswith(PREFIX) or not name.endswith(SUFFIX):
        return None
    path = os.path.join(directory, name)
    return path if os.path.isfile(path) else None


def inside(member):
    """True when a member is one this script would have written, and nowhere else.

    Checked before anything is extracted: an archive that came from somewhere
    else — or was edited by hand — is refused rather than trusted, since a
    restore writes into the user's config tree.
    """
    if member.name.startswith("/") or ".." in member.name.split("/"):
        return False
    if member.issym() or member.islnk():
        return False
    top = member.name.split("/", 1)[0]
    return top == SHELL_MEMBER or member.name in STATE_MEMBERS


def extract(tar, where):
    """Extract into `where`, letting the interpreter refuse unsafe members too."""
    try:
        tar.extractall(where, filter="data")
    except TypeError:  # an interpreter without extraction filters
        tar.extractall(where)


def copy_over(source, target):
    """Write every file under `source` into `target`; return what was written.

    Directories are created as needed and an existing file is replaced, but
    nothing under `target` is deleted: a rollback is not allowed to take a file
    that arrived after the backup with it.
    """
    written = []
    for folder, dirs, files in os.walk(source):
        dirs[:] = [folder for folder in dirs if folder not in SKIP_DIRS]
        relative = os.path.relpath(folder, source)
        into = target if relative == "." else os.path.join(target, relative)
        os.makedirs(into, exist_ok=True)
        for name in files:
            if name.endswith(SKIP_SUFFIXES):
                continue
            shutil.copy2(os.path.join(folder, name), os.path.join(into, name))
            written.append(os.path.relpath(os.path.join(into, name), target))
    return written


def restore(args, archive, name):
    """Put an archive's contents back where the shell reads them from."""
    staging = tempfile.mkdtemp(prefix="silhouette-restore-")
    try:
        with tarfile.open(archive) as tar:
            strange = [entry.name for entry in tar.getmembers() if not inside(entry)]
            if strange:
                return error("The archive holds something this script did not write: "
                             + strange[0])
            extract(tar, staging)

        written = []
        tree = os.path.join(staging, SHELL_MEMBER)
        if os.path.isdir(tree):
            written = copy_over(tree, os.path.abspath(args.shell))

        flags = False
        for member, target in state_files(os.path.abspath(args.state)):
            source = os.path.join(staging, member)
            if not os.path.isfile(source) and member == WALLPAPER_MEMBER:
                # An archive from before the rename spells this member
                # `ricelin-wallpaper`; it still restores.
                source = os.path.join(staging, LEGACY_WALLPAPER_MEMBER)
            if not os.path.isfile(source):
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(source, target)
            flags = flags or member == FLAG_MEMBER
    except (OSError, tarfile.TarError) as problem:
        return error("Could not restore %s: %s" % (name, problem))
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    return emit({"status": "ok", "name": name, "files": len(written), "flags": flags})


def remove(args, archive, name):
    """Delete one archive."""
    try:
        os.remove(archive)
    except OSError as problem:
        return error("Could not delete %s: %s" % (archive, problem))
    return emit({"status": "ok", "name": name})


def discard(path):
    try:
        os.remove(path)
    except OSError:
        pass


def main():
    base = defaults()
    parser = argparse.ArgumentParser(
        description="Back up and restore the silhouette-shell config.")
    parser.add_argument("action", choices=["create", "list", "restore", "remove"],
                        help="what to do")
    parser.add_argument("name", nargs="?",
                        help="the archive to restore or remove, by file name")
    parser.add_argument("--shell", default=base["shell"], help="the shell tree")
    parser.add_argument("--state", default=base["state"], help="the shell's state dir")
    parser.add_argument("--dir", default=base["dir"], help="where archives live")
    args = parser.parse_args()

    if args.action == "create":
        return create(args)
    if args.action == "list":
        return emit({"status": "ok", "backups": backups(args.dir)})

    if not args.name:
        return error("name the backup to %s" % args.action)
    archive = resolve(args.dir, args.name)
    if archive is None:
        return error("no backup named %s in %s" % (args.name, args.dir))
    if args.action == "restore":
        return restore(args, archive, args.name)
    return remove(args, archive, args.name)


if __name__ == "__main__":
    sys.exit(main())
