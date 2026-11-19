#!/usr/bin/env python3

import json
import os
import platform
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class Command:
    program: str
    args: tuple = ()
    privileged: bool = False
    environment: dict = field(default_factory=dict)

    def argv(self):
        return [self.program, *self.args]

    def display(self):
        argv = self.argv()
        if self.privileged:
            argv.insert(0, privilege_helper() or "pkexec")
        return " ".join(argv)


@dataclass(frozen=True)
class Backend:
    check: Command
    parse: object
    apply: tuple
    minimal: tuple = None
    success_codes: tuple = (0,)
    note: str = ""
    reboot_check: Command = None


def command(program, *args, privileged=False, environment=None):
    return Command(program, tuple(args), privileged, environment or {})


def run(cmd, environment=None):
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=environment,
        )
    except OSError as error:
        return 127, str(error)
    return result.returncode, result.stdout


def privilege_helper():
    return next((name for name in ("pkexec", "doas", "sudo") if shutil.which(name)), None)


def run_command(spec):
    argv = spec.argv()
    environment = None
    if spec.privileged:
        helper = privilege_helper()
        if not helper:
            return 127, "No supported privilege helper found (pkexec, doas, or sudo)."
        argv = [helper]
        if spec.environment:
            argv.extend(["env", *(f"{key}={value}" for key, value in spec.environment.items())])
        argv.extend(spec.argv())
    elif spec.environment:
        environment = os.environ.copy()
        environment.update(spec.environment)
    return run(argv, environment)


def distro_family():
    release_path = Path(os.environ.get("SILHOUETTE_OS_RELEASE", "/etc/os-release"))
    try:
        values = {}
        for line in release_path.read_text().splitlines():
            key, separator, value = line.partition("=")
            if separator:
                values[key] = value.strip().strip("\"'").lower()
    except OSError:
        values = {}

    identity = {values.get("ID", ""), *values.get("ID_LIKE", "").split()}
    if identity.intersection({"fedora", "rhel", "centos"}):
        return "fedora"
    if "alpine" in identity:
        return "alpine"
    if identity.intersection({"artix", "arch"}):
        return "arch"
    if identity.intersection({"debian", "ubuntu"}):
        return "debian"
    if any(value == "suse" or value.startswith("opensuse") for value in identity):
        return "suse"
    if "gentoo" in identity:
        return "gentoo"
    if "void" in identity:
        return "void"

    return {
        "FreeBSD": "freebsd",
        "OpenBSD": "openbsd",
        "NetBSD": "netbsd",
        "DragonFly": "dragonfly",
        "Darwin": "darwin",
    }.get(platform.system(), "unknown")


def parse_check(output):
    packages = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith(("Last metadata", "Obsoleting")):
            continue
        parts = line.split()
        if len(parts) >= 3:
            packages.append(parts[0])
    return packages


def parse_emerge_check(output):
    entry = re.compile(r"^\s*\[(?:ebuild|binary)\s+[^]]+\]\s+(\S+)")
    return [match.group(1) for line in output.splitlines() if (match := entry.match(line))]


def parse_arch_check(output):
    return [parts[0] for line in output.splitlines() if (parts := line.split()) and not parts[0].startswith("::")]


def parse_debian_check(output):
    packages = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] == "Inst":
            packages.append(fields[1])
    return packages


def parse_suse_check(output):
    packages = []
    for line in output.splitlines():
        fields = [field.strip() for field in line.split("|")]
        if len(fields) >= 6 and fields[0] == "v" and fields[1] != "Name":
            packages.append(fields[1])
    return packages


def parse_alpine_check(output):
    return [
        fields[0]
        for line in output.splitlines()
        if "[upgradable from:" in line and (fields := line.split())
    ]


def parse_void_check(output):
    packages = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1] in {"update", "install", "reinstall"}:
            packages.append(fields[0])
    return packages


def parse_pkg_check(output):
    packages = []
    for line in output.splitlines():
        line = line.strip()
        if " -> " in line:
            name = line.split(" -> ", 1)[0].split(": ", 1)[0].split()
            if name:
                packages.append(name[-1])
            continue
        for prefix in ("Upgrading ", "Installing ", "Reinstalling "):
            if line.startswith(prefix):
                packages.append(line[len(prefix):].split()[0])
                break
    return packages


def parse_openbsd_check(output):
    packages = []
    for line in output.splitlines():
        line = line.strip()
        match = re.search(r"\b(?:Update|Updating)\s+(?:\d+:\s*)?([A-Za-z0-9_.+-]+)", line)
        if match:
            packages.append(match.group(1))
        elif " -> " in line:
            packages.append(line.split(" -> ", 1)[0].split()[-1])
    return packages


def parse_pkgin_check(output):
    packages = []
    for line in output.splitlines():
        line = line.strip()
        if (
            not line
            or line.lower().startswith(("calculating", "packages to be", "nothing to do"))
            or line.endswith(":")
        ):
            continue
        package = line.split()[0]
        if package[0].isalnum():
            packages.append(package)
    return packages


def parse_brew_check(output):
    value = json.loads(output)
    packages = []
    for key in ("formulae", "casks"):
        for item in value.get(key, []):
            name = item.get("name") or item.get("token")
            if name:
                packages.append(name)
    return packages


NONINTERACTIVE = {"DEBIAN_FRONTEND": "noninteractive"}


def backend(family):
    if family == "fedora":
        return Backend(
            command("dnf", "check-update"),
            parse_check,
            (
                command("dnf", "upgrade", "-y", privileged=True),
                command("dnf", "autoremove", "-y", privileged=True),
                command("dnf", "clean", "all", privileged=True),
            ),
            minimal=(
                command("dnf", "upgrade-minimal", "-y", privileged=True),
                command("dnf", "autoremove", "-y", privileged=True),
                command("dnf", "clean", "all", privileged=True),
            ),
            success_codes=(0, 100),
            reboot_check=command("needs-restarting", "-r"),
        )
    if family == "gentoo":
        return Backend(
            command("emerge", "--pretend", "--update", "--deep", "--with-bdeps=y", "@world"),
            parse_emerge_check,
            (command("emerge", "--ask=n", "--update", "--deep", "--with-bdeps=y", "--newuse", "@world", privileged=True),),
            note="Uses local Portage metadata; sync repositories before checking for the latest updates.",
        )
    if family == "arch":
        check = command("checkupdates") if shutil.which("checkupdates") else command("pacman", "-Qu")
        return Backend(
            check,
            parse_arch_check,
            (command("pacman", "-Syu", "--noconfirm", privileged=True),),
            success_codes=(0, 2) if check.program == "checkupdates" else (0,),
        )
    if family == "debian":
        return Backend(
            command("apt-get", "--just-print", "upgrade"),
            parse_debian_check,
            (
                command("apt-get", "upgrade", "-y", "-o", "Dpkg::Options::=--force-confold", privileged=True, environment=NONINTERACTIVE),
                command("apt-get", "autoremove", "-y", privileged=True, environment=NONINTERACTIVE),
                command("apt-get", "clean", privileged=True, environment=NONINTERACTIVE),
            ),
        )
    if family == "alpine":
        return Backend(
            command("apk", "list", "--upgradable"),
            parse_alpine_check,
            (command("apk", "upgrade", privileged=True),),
        )
    if family == "suse":
        return Backend(
            command("zypper", "--non-interactive", "list-updates"),
            parse_suse_check,
            (
                command("zypper", "--non-interactive", "update", "-y", privileged=True),
                command("zypper", "--non-interactive", "clean", "--all", privileged=True),
            ),
            minimal=(
                command("zypper", "--non-interactive", "patch", "--category", "security", "-y", privileged=True),
            ),
        )
    if family == "void":
        return Backend(
            command("xbps-install", "-M", "-u", "-n"),
            parse_void_check,
            (command("xbps-install", "-S", "-u", "-y", privileged=True),),
        )
    if family in {"freebsd", "dragonfly"}:
        return Backend(
            command("pkg", "upgrade", "--dry-run"),
            parse_pkg_check,
            (
                command("pkg", "upgrade", "-y", privileged=True),
                command("pkg", "autoremove", "-y", privileged=True),
            ),
        )
    if family == "openbsd":
        return Backend(
            command("pkg_add", "-u", "-n", "-s", "-v"),
            parse_openbsd_check,
            (command("pkg_add", "-u", "-I", privileged=True),),
        )
    if family == "netbsd":
        return Backend(
            command("pkgin", "-p", "-l", "<", "list"),
            parse_pkgin_check,
            (command("pkgin", "-y", "upgrade", privileged=True),),
        )
    if family == "darwin":
        return Backend(
            command("brew", "outdated", "--json=v2"),
            parse_brew_check,
            (command("brew", "upgrade"),),
        )
    return None


def check():
    family = distro_family()
    plan = backend(family)
    if plan is None:
        return {
            "status": "error",
            "error": f"Package updates are not supported for {family}.",
        }
    code, output = run_command(plan.check)
    if code not in plan.success_codes:
        return {"status": "error", "error": output.strip() or f"{plan.check.display()} exited with status {code}"}
    try:
        packages = list(dict.fromkeys(plan.parse(output)))
    except (ValueError, KeyError, TypeError) as error:
        return {"status": "error", "error": f"Could not parse {family} update list: {error}"}
    result = {
        "status": "ok",
        "updates": len(packages),
        "packages": packages,
        "supportsMinimal": plan.minimal is not None,
    }
    if plan.note:
        result["note"] = plan.note
    return result


def apply(minimal=False):
    family = distro_family()
    plan = backend(family)
    if plan is None:
        message = f"Package updates are not supported for {family}."
        return {
            "status": "error",
            "applied": False,
            "rebootNeeded": False,
            "results": [{"command": "package manager", "success": False, "output": message}],
        }
    if minimal and plan.minimal is None:
        message = f"{family.capitalize()} does not provide a generic security-only package update."
        return {
            "status": "error",
            "applied": False,
            "rebootNeeded": False,
            "results": [{"command": "package manager", "success": False, "output": message}],
        }

    commands = plan.minimal if minimal else plan.apply
    results = []
    for spec in commands:
        code, output = run_command(spec)
        results.append(
            {
                "command": spec.display(),
                "success": code == 0,
                "output": output,
            }
        )
        if code != 0:
            break
    applied = bool(results) and all(result["success"] for result in results)
    reboot_needed = False
    if plan.reboot_check and shutil.which(plan.reboot_check.program):
        reboot_needed = run_command(plan.reboot_check)[0] == 1
    return {
        "status": "ok" if applied else "error",
        "applied": applied,
        "rebootNeeded": reboot_needed,
        "results": results,
    }


def rust_enabled():
    if os.environ.get("SILHOUETTE_FORCE_PYTHON") == "1":
        return False
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    flags = state_home / "silhouette" / "flags.json"
    try:
        settings = json.loads(flags.read_text())
    except (OSError, ValueError):
        settings = {}
    return settings.get("useRustTools") is not False and settings.get("rustWallpapers") is not False


def valid_rust_result(operation, value):
    if not isinstance(value, dict) or not isinstance(value.get("status"), str):
        return False
    if value["status"] not in {"ok", "error"}:
        return False
    if operation == "check" and value["status"] == "error":
        return isinstance(value.get("error"), str) and bool(value["error"])
    if operation == "check":
        return (
            type(value.get("updates")) is int
            and value["updates"] >= 0
            and isinstance(value.get("packages"), list)
            and all(isinstance(package, str) for package in value["packages"])
            and value["updates"] == len(value["packages"])
            and isinstance(value.get("supportsMinimal"), bool)
            and (value.get("note") is None or isinstance(value.get("note"), str))
        )
    results = value.get("results")
    return (
        isinstance(value.get("applied"), bool)
        and isinstance(value.get("rebootNeeded"), bool)
        and isinstance(results, list)
        and all(
            isinstance(item, dict)
            and isinstance(item.get("command"), str)
            and isinstance(item.get("success"), bool)
            and isinstance(item.get("output"), str)
            for item in results
        )
    )


def run_rust(operation):
    if not rust_enabled():
        return None
    rust_bin = Path(__file__).resolve().parent / "bin" / "silhouette-tools"
    if not rust_bin.is_file() or not os.access(rust_bin, os.X_OK):
        return None
    try:
        result = subprocess.run(
            [str(rust_bin), "package-updates", operation],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except OSError as error:
        print(
            f"silhouette-update: cannot start Rust updater: {error}; using Python fallback",
            file=sys.stderr,
        )
        return None

    try:
        value = json.loads(result.stdout)
    except (TypeError, ValueError):
        value = None
    if valid_rust_result(operation, value):
        if result.stderr.strip():
            print(result.stderr.rstrip(), file=sys.stderr)
        return value

    if result.stderr.strip():
        print(result.stderr.rstrip(), file=sys.stderr)
    print(
        "silhouette-update: Rust updater returned invalid output; using Python fallback",
        file=sys.stderr,
    )
    return None


def usage():
    print("usage:")
    print("  silhouette-update.py check")
    print("  silhouette-update.py apply")
    print("  silhouette-update.py apply-minimal")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"check", "apply", "apply-minimal"}:
        usage()
        return 1
    operation = sys.argv[1]
    result = run_rust(operation)
    if result is not None:
        print(json.dumps(result))
        return 0
    result = check() if operation == "check" else apply(operation == "apply-minimal")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
