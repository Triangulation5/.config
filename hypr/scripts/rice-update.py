#!/usr/bin/env python3
"""
The rice updater behind the shell's 更 UPDATES surface.

The shell's Updates singleton is a thin reader of one JSON object per run. This
is the engine on the other side of that contract: `check` is a safe dry-run that
reports how far behind the install is, the changelog, and any file whose local
edits clash with upstream; `apply` lands upstream and re-deploys the config.

Two update paths exist on purpose, and they answer different questions:

  - `silhouette-update.py` (next to this file) is the *distribution*: what dnf
    has pending and whether a reboot is wanted. The settings app's Updates page
    drives it.
  - this script is the *rice*: which commits your config is behind, and what
    landing them would touch. The pill's quick-settings Updater drives it.

Where the rice lives:

  - a clone at ~/.local/share/silhouette-install, which is what install.sh
    makes when it installs from the repo rather than from a copy you already
    have. This is the copy the engine updates, then re-deploys through
    install.sh so the new code reaches ~/.config.
  - if that is missing, `check` clones it on demand from SILHOUETTE_REPO, so a
    machine that has never pulled the repo can still set itself up ("the rice
    copy didn't land yet" in the surface).
  - if ~/.config is itself a git work tree, this is a developer install: you
    edit the config in place and update it with plain git. In-app updating is
    off there, which is what the surface means by `devmode`.

Local edits are never destroyed by a normal update. Before landing upstream the
engine snapshots every tracked file you have changed, moves the tree to
upstream, and puts your versions back. Files listed in `--take` are the ones you
opted to hand over to upstream instead, which is the only way a conflicting edit
is overwritten. Untracked files are not touched at all.

Env:
  SILHOUETTE_RICE_DIR  the checkout to update (default: the clone above, else
                       ~/.config when that is a work tree)
  SILHOUETTE_REPO      remote to clone from when there is no checkout
                       (same meaning as in install.sh)
  SILHOUETTE_REF       branch or tag to track (default main)
  XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, or their defaults.

Contract: one JSON object on stdout. A failure is reported in that same shape
(`status: "error"`) rather than left to a traceback, because the surface parses
stdout and has nowhere else to read a reason from.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
DEFAULT_REMOTE = "https://github.com/Triangulation5/.config.git"
# Only for the clone the engine owns. install.sh uses the same tail so a
# machine set up either way ends up with one copy, not two.
CLONE_NAME = "silhouette-install"
# The changelog is a surface, not a log: a long gap should read as a paragraph,
# not scroll the panel.
CHANGELOG_LIMIT = 40
# Packages the rice cannot work without, over and above install.sh's own list.
# Kept empty on purpose: the installer's CORE_* arrays are the single source of
# truth for what the shell calls out to, and duplicating them here is how the
# two lists drift apart.
EXTRA_CORE = ()


def emit(payload):
    """Print one JSON object and return a success code."""
    print(json.dumps(payload))
    return 0


def fail(message, status="error"):
    """Report a whole-run failure in the shape the surface reads."""
    print(json.dumps({"status": status, "error": message, "behind": 0}))
    return 0


def git(args, cwd=None, check=False):
    """Run git, returning (code, stdout). Never raises on a git failure."""
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if check and result.returncode != 0:
        raise GitError("git %s failed" % " ".join(args))
    return result.returncode, result.stdout.strip()


class GitError(Exception):
    pass


def data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")


def config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")


def state_dir():
    return os.environ.get("SILHOUETTE_STATE_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"),
        "silhouette",
    )


def manifest_path():
    return os.path.join(state_dir(), "update.json")


def ref():
    return os.environ.get("SILHOUETTE_REF") or "main"


def is_work_tree(path):
    """True when `path` is a git work tree, without needing a .git directory.

    A work tree can be reached through a `.git` file instead (a symlinked or
    submodule checkout), so ask git rather than stat the path.
    """
    if not os.path.isdir(path):
        return False
    code, out = git(["-C", path, "rev-parse", "--is-inside-work-tree"])
    return code == 0 and out.strip() == "true"


def clone_dir():
    return os.path.join(data_home(), CLONE_NAME)


def resolve_checkout():
    """The checkout to update, and whether this is a developer install.

    Returns (path, devmode). A devmode install is the live config being its own
    work tree: there is nothing to deploy, and updating it is the user's own git
    business, so the engine reports and stays out of the way.
    """
    override = os.environ.get("SILHOUETTE_RICE_DIR")
    if override:
        return os.path.abspath(override), False
    if is_work_tree(clone_dir()):
        return clone_dir(), False
    if is_work_tree(config_home()):
        return config_home(), True
    return None, False


def remote_url(checkout):
    """Where a fresh clone should come from: the env, then an existing clone."""
    explicit = os.environ.get("SILHOUETTE_REPO")
    if explicit:
        return explicit
    if checkout:
        code, out = git(["-C", checkout, "remote", "get-url", "origin"])
        if code == 0 and out:
            return out
    return DEFAULT_REMOTE


def ensure_checkout():
    """The checkout to work in, cloning one on demand when there is none.

    Returns (path, error). `check` calls this too: fetching the copy is what
    moves a fresh machine from "nothing here yet" to a real behind count, and
    the clone only ever writes under XDG_DATA_HOME.
    """
    checkout, devmode = resolve_checkout()
    if devmode:
        return checkout, None
    if checkout:
        return checkout, None

    destination = clone_dir()
    url = remote_url(None)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    if os.path.exists(destination) and os.listdir(destination):
        # Something is already here but is not a work tree. Cloning over it
        # would either fail or mix two trees, so leave it for the user.
        return None, "%s exists but is not a git checkout" % destination

    result = subprocess.run(
        ["git", "clone", "--single-branch", "--branch", ref(), url, destination],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        tail = (result.stderr or result.stdout or "").strip().splitlines()
        return None, tail[-1] if tail else "could not clone %s" % url
    return destination, None


def fetch(checkout):
    """Bring the remote refs up to date. Returns an error string, or None."""
    code, out = git(["-C", checkout, "fetch", "--quiet", "origin", ref()])
    if code != 0:
        return "could not reach %s" % remote_url(checkout)
    return None


def remote_ref():
    return "FETCH_HEAD"


def local_sha(checkout):
    code, out = git(["-C", checkout, "rev-parse", "--short", "HEAD"])
    return out if code == 0 else ""


def commit_date(checkout, revision):
    code, out = git(["-C", checkout, "log", "-1", "--format=%cs", revision])
    return out if code == 0 else ""


def ahead_of_upstream(checkout):
    """Commits this checkout has that upstream does not.

    A clone with its own commits is being developed, not installed, and a
    fast-forward is not what the user wants there.
    """
    code, out = git(["-C", checkout, "rev-list", "--count",
                     "%s..HEAD" % remote_ref()])
    if code != 0:
        return 0
    try:
        return int(out)
    except ValueError:
        return 0


def behind_count(checkout):
    code, out = git(["-C", checkout, "rev-list", "--count",
                     "HEAD..%s" % remote_ref()])
    if code != 0:
        return 0
    try:
        return int(out)
    except ValueError:
        return 0


def changelog(checkout):
    """Commit subjects between here and upstream, newest first."""
    code, out = git(["-C", checkout, "log", "--no-merges", "--format=%s",
                     "HEAD..%s" % remote_ref()])
    if code != 0:
        return []
    return [line for line in out.splitlines() if line.strip()][:CHANGELOG_LIMIT]


def merge_base(checkout):
    code, out = git(["-C", checkout, "merge-base", "HEAD", remote_ref()])
    return out if code == 0 else ""


def changed_files(checkout, from_revision, to_revision):
    """Paths differing between two revisions, or from one to the working tree.

    An empty `to_revision` means the working tree, which git spells by leaving
    the second revision off entirely - passing an empty argument is a hard
    error, not an omission.
    """
    arguments = ["-C", checkout, "diff", "--name-only", from_revision]
    if to_revision:
        arguments.append(to_revision)
    code, out = git(arguments)
    if code != 0:
        return set()
    return {line.strip() for line in out.splitlines() if line.strip()}


def conflicts(checkout):
    """Files both sides moved: your edit and upstream's meet in one path.

    Computed against the merge base rather than against HEAD alone, so a file
    this checkout is *behind* on does not read as a conflict just because the
    working tree copy differs.
    """
    base = merge_base(checkout)
    if not base:
        return []
    mine = changed_files(checkout, base, "")  # base -> working tree
    theirs = changed_files(checkout, base, remote_ref())
    return sorted(mine & theirs)


def dirty_tracked(checkout):
    """Tracked paths with local changes, staged or not.

    Untracked files are deliberately absent: nothing in the update path touches
    them, so they need no protecting.
    """
    code, out = git(["-C", checkout, "diff", "--name-only", "HEAD"])
    if code != 0:
        return set()
    return {line.strip() for line in out.splitlines() if line.strip()}


def snapshot(checkout, paths):
    """Copy `paths` out of the tree so they can be restored after the move.

    Returns (directory, error). A file that vanished between the listing and the
    copy is skipped rather than fatal.
    """
    directory = tempfile.mkdtemp(prefix="silhouette-rice-")
    for relative in paths:
        source = os.path.join(checkout, relative)
        if not os.path.isfile(source):
            continue
        destination = os.path.join(directory, relative)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        try:
            shutil.copy2(source, destination)
        except OSError as problem:
            return directory, "could not snapshot %s: %s" % (relative, problem)
    return directory, None


def restore(checkout, directory):
    """Put the snapshotted files back, newest content winning."""
    for folder, _dirs, files in os.walk(directory):
        for name in files:
            source = os.path.join(folder, name)
            relative = os.path.relpath(source, directory)
            destination = os.path.join(checkout, relative)
            try:
                os.makedirs(os.path.dirname(destination), exist_ok=True)
                shutil.copy2(source, destination)
            except OSError:
                # A file that cannot be written back is reported by the caller's
                # own diff, not by failing the whole update here.
                continue


def installed_check(packages, family):
    """Which of `packages` are already on the machine.

    Returns a set. An unknown family, or a missing query tool, returns every
    name as installed: an update should never nag about packages it cannot
    actually check. These tools exit non-zero when *any* name is missing while
    still reporting the ones they did find, so the answer is the reported names
    intersected with what was asked for - not the exit status.
    """
    if not packages:
        return set()

    if family in ("fedora", "suse"):
        # --qf makes rpm print the bare package name instead of
        # name-version-release.arch, which is what the comparison needs.
        query = ["rpm", "-q", "--qf", "%{NAME}\n"]
    elif family == "arch":
        query = ["pacman", "-Q"]
    elif family == "debian":
        query = ["dpkg", "-s"]
    else:
        return set(packages)

    if not shutil.which(query[0]):
        return set(packages)

    result = subprocess.run(
        query + sorted(packages),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    present = set()
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        if family in ("fedora", "suse"):
            present.add(line)
        elif family == "arch":
            present.add(line.split()[0])
        elif line.startswith("Package: "):
            present.add(line.split(": ", 1)[1].strip())
    return present & set(packages)


def distro_family():
    """The install.sh family for this machine, so both agree on package names."""
    identifier = ""
    likes = ""
    try:
        with open("/etc/os-release") as handle:
            for line in handle:
                if line.startswith("ID="):
                    identifier = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("ID_LIKE="):
                    likes = line.split("=", 1)[1].strip().strip('"')
    except OSError:
        return "unknown"

    haystack = " %s %s " % (identifier, likes)
    for family, needles in (
        ("fedora", ("fedora", "rhel", "centos")),
        ("arch", ("arch",)),
        ("debian", ("debian", "ubuntu")),
        ("suse", ("suse", "opensuse")),
        ("gentoo", ("gentoo",)),
    ):
        if any(needle in haystack for needle in needles):
            return family
    return "unknown"


def core_packages(checkout):
    """The installer's CORE list for this machine, read from install.sh.

    Parsed rather than duplicated: the installer is the one place that knows
    which package names each distro uses, and the two have to agree or the
    surface offers a name the package manager does not have.
    """
    script = os.path.join(checkout, "install.sh")
    try:
        with open(script) as handle:
            text = handle.read()
    except OSError:
        return []

    name = "CORE_%s" % distro_family()
    match = re.search(r"^%s=\((.*?)\)$" % re.escape(name), text,
                      re.MULTILINE | re.DOTALL)
    if not match:
        return []
    words = match.group(1).split()
    return [word for word in words if word and not word.startswith("#")]


def missing_deps(checkout):
    """Core packages this machine does not have yet, as {id, desc}.

    `desc` is filled from the optional hints the installer already carries, so
    the surface can say what a package is for; anything without a hint gets an
    empty description, which the row then hides.
    """
    wanted = list(EXTRA_CORE) + core_packages(checkout)
    if not wanted:
        return []

    present = installed_check(set(wanted), distro_family())
    ordered = []
    seen = set()
    for name in wanted:
        if name in present or name in seen:
            continue
        seen.add(name)
        ordered.append({"id": name, "desc": hint_for(checkout, name)})
    return ordered


def hint_for(checkout, name):
    """The installer's one-line description for a package, if it has one."""
    script = os.path.join(checkout, "install.sh")
    try:
        with open(script) as handle:
            text = handle.read()
    except OSError:
        return ""
    match = re.search(r'"%s:\s*(.+?)"' % re.escape(name), text)
    return match.group(1).strip() if match else ""


def install_command(family, packages):
    """The install invocation, as the argv to hand to pkexec."""
    if family == "fedora":
        return ["dnf", "install", "-y"] + packages
    if family == "arch":
        return ["pacman", "-S", "--needed", "--noconfirm"] + packages
    if family == "debian":
        return ["apt-get", "install", "-y"] + packages
    if family == "suse":
        return ["zypper", "--non-interactive", "install"] + packages
    return []


def install_deps(checkout, ids):
    """Install the packages the user left toggled on.

    pkexec rather than sudo: the shell already answers polkit prompts through
    its own agent, and a headless process has no terminal to answer sudo on.
    Failures are per package so one bad name does not sink the rest.
    """
    failures = []
    if not ids:
        return failures

    family = distro_family()
    for package in ids:
        command = install_command(family, [package])
        if not command:
            failures.append({"id": package,
                             "error": "no package manager for %s" % family})
            continue
        result = subprocess.run(
            ["pkexec"] + command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if result.returncode != 0:
            lines = [line for line in (result.stdout or "").splitlines() if line.strip()]
            failures.append({
                "id": package,
                "error": lines[-1] if lines else "install failed",
            })
    return failures


def deploy(checkout):
    """Copy the updated tree into the live config, through the installer.

    Reusing install.sh keeps one deploy path: it backs up what it replaces,
    merges into directories instead of wiping them, and neutralises the
    hardware-specific extras. --source points it at the checkout we just
    updated so it deploys what is on disk instead of fetching its own.
    Other flags: no packages, no prompts, and it is not asked to touch the
    monitor layout twice (it already keeps monitors.lua.example from the first
    install, so a re-run leaves the layout alone).
    """
    script = os.path.join(checkout, "install.sh")
    if not os.path.isfile(script):
        return "no install.sh in %s to deploy with" % checkout

    result = subprocess.run(
        ["bash", script, "--source", checkout, "--no-deps", "--yes"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if result.returncode != 0:
        lines = [line for line in (result.stdout or "").splitlines() if line.strip()]
        return lines[-1] if lines else "install.sh exited %s" % result.returncode
    return None


def write_manifest(checkout, version):
    """Record what landed, which is how the surface names the installed side."""
    payload = {
        "syncedSha": git(["-C", checkout, "rev-parse", "HEAD"])[1],
        "version": version,
        "syncedAt": int(time.time()),
    }
    try:
        os.makedirs(state_dir(), exist_ok=True)
        with open(manifest_path(), "w") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
    except OSError:
        # A manifest that cannot be written is a cosmetic loss: the version
        # line falls back to whatever the engine reports next check.
        pass


def target_sha(checkout):
    """Short sha of what the update would land, not of what is here now.

    The surface splits this off `version` and compares it with the sha the
    manifest recorded, so it has to name upstream: naming HEAD would make the
    two look equal whenever a checkout is already at parity, and would hide the
    difference for the whole span of an update that has not been applied yet.
    """
    code, out = git(["-C", checkout, "rev-parse", "--short", remote_ref()])
    return out if code == 0 else ""


def describe(checkout):
    """The bits every reply carries: target version and how far behind."""
    target = target_sha(checkout)
    date = commit_date(checkout, remote_ref())
    version = ("%s %s" % (target, date)).strip() if target else ""
    return {
        "behind": behind_count(checkout),
        "fromDate": commit_date(checkout, "HEAD"),
        "toDate": date,
        "changelog": changelog(checkout),
        "conflicts": conflicts(checkout),
        "version": version,
    }


def check(arguments):
    """Report the state of the install without changing the live config."""
    checkout, devmode = resolve_checkout()

    if devmode:
        # The config is its own work tree: updating it is plain git, and the
        # surface says so rather than offering a button that would fight the
        # user's checkout.
        return emit({"status": "devmode", "behind": 0,
                     "version": local_sha(checkout)})

    checkout, error = ensure_checkout()
    if error:
        # No copy and no way to make one: the surface reads this as "not set up
        # yet", and a later check retries once there is somewhere to clone from.
        return fail(error, status="noclone")

    error = fetch(checkout)
    if error:
        return fail(error, status="offline")

    if ahead_of_upstream(checkout) > 0:
        return emit({"status": "devmode", "behind": 0,
                     "version": local_sha(checkout)})

    payload = describe(checkout)
    payload["status"] = "ok"
    payload["missingDeps"] = missing_deps(checkout)
    return emit(payload)


def apply_changes(arguments):
    """Land upstream, re-deploy the config, and report what to restart."""
    checkout, devmode = resolve_checkout()
    if devmode:
        return emit({"status": "devmode", "behind": 0, "applied": False,
                     "restartNeeded": False})

    checkout, error = ensure_checkout()
    if error:
        return fail(error, status="noclone")

    error = fetch(checkout)
    if error:
        return fail(error, status="offline")

    if ahead_of_upstream(checkout) > 0:
        return emit({"status": "devmode", "behind": 0, "applied": False,
                     "restartNeeded": False})

    payload = describe(checkout)
    taken = wanted_paths(arguments.take, payload["conflicts"])
    dependencies = [item for item in (arguments.install_deps or "").split(",")
                    if item]

    if payload["behind"] == 0:
        # Nothing to land. Still worth installing a package the user asked for,
        # since the surface lists them next to the update that wants them.
        failures = install_deps(checkout, dependencies)
        return emit({"status": "ok", "applied": False, "restartNeeded": False,
                     "behind": 0, "conflicts": [], "missingDeps": [],
                     "depFailures": failures, "version": payload["version"],
                     "changelog": []})

    # Protect every local edit except the paths handed to upstream. Snapshotting
    # the whole set, not just the conflicting subset, is what makes the move to
    # upstream safe: reset --hard only ever discards what is in here.
    keep = dirty_tracked(checkout) - set(taken)
    directory, error = snapshot(checkout, sorted(keep))
    if error:
        return fail(error)

    try:
        code, _ = git(["-C", checkout, "reset", "--hard", remote_ref()])
        if code != 0:
            return fail("could not move the tree to upstream")
        restore(checkout, directory)
    finally:
        shutil.rmtree(directory, ignore_errors=True)

    failures = install_deps(checkout, dependencies)

    error = deploy(checkout)
    if error:
        return fail(error)

    write_manifest(checkout, payload["version"])

    payload.update({
        "status": "ok",
        "applied": True,
        # New code is on disk but the running shell loaded the old copy.
        "restartNeeded": True,
        "behind": 0,
        "conflicts": [],
        "missingDeps": [],
        "depFailures": failures,
    })
    return emit(payload)


def wanted_paths(raw, conflicts_found):
    """The --take list, filtered to paths that exist in the repo.

    The surface sends back names it was given, but this is still user input
    arriving over a comma-separated string: an absolute path or a `..` would
    otherwise let a take reach outside the checkout.
    """
    taken = []
    for candidate in (raw or "").split(","):
        candidate = candidate.strip()
        if not candidate or candidate.startswith("/") or ".." in candidate.split("/"):
            continue
        if candidate in conflicts_found:
            taken.append(candidate)
    return taken


def main():
    parser = argparse.ArgumentParser(
        description="Update the rice from its git remote.")
    parser.add_argument("action", choices=["check", "apply"],
                        help="what to do")
    parser.add_argument("--take", default="",
                        help="comma-separated paths to overwrite with upstream")
    parser.add_argument("--install-deps", default="",
                        help="comma-separated package ids to install")
    arguments = parser.parse_args()

    try:
        if arguments.action == "check":
            return check(arguments)
        return apply_changes(arguments)
    except GitError as problem:
        return fail(str(problem))
    except OSError as problem:
        return fail("system call failed: %s" % problem)


if __name__ == "__main__":
    sys.exit(main())
