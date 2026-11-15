#!/usr/bin/env python3

import json
import re
import shutil
import subprocess
import sys


def run(cmd):
    """Run a command and capture stdout/stderr."""
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except OSError as error:
        return 127, str(error)
    return result.returncode, result.stdout


def parse_check(output):
    """Extract package names from `dnf check-update`."""
    packages = []

    for line in output.splitlines():
        line = line.strip()

        if (
            not line
            or line.startswith("Last metadata")
            or line.startswith("Obsoleting")
        ):
            continue

        parts = line.split()

        if len(parts) >= 3:
            packages.append(parts[0])

    return packages


def parse_emerge_check(output):
    """Extract package atoms from an emerge pretend-update listing."""
    packages = []
    entry = re.compile(r"^\s*\[(?:ebuild|binary)\s+[A-Z ]+\]\s+(\S+)")
    for line in output.splitlines():
        match = entry.match(line)
        if match:
            packages.append(match.group(1))
    return packages


def distro_family():
    """Return the package family supported by this updater."""
    try:
        with open("/etc/os-release") as handle:
            values = {}
            for line in handle:
                key, separator, value = line.partition("=")
                if separator:
                    values[key] = value.strip().strip('"').strip("'").lower()
    except OSError:
        return "unknown"

    identity = values.get("ID", "")
    likes = values.get("ID_LIKE", "").split()
    if identity in ("gentoo", "funtoo") or "gentoo" in likes:
        return "gentoo"
    if identity in ("fedora", "rhel", "centos") or any(
        like in ("fedora", "rhel", "centos") for like in likes
    ):
        return "fedora"
    return "unknown"


def check():
    family = distro_family()
    if family == "fedora":
        code, output = run(["dnf", "check-update"])
        if code in (0, 100):
            packages = parse_check(output) if code == 100 else []
            return {
                "status": "ok",
                "updates": len(packages),
                "packages": packages,
                "supportsMinimal": True,
            }
    elif family == "gentoo":
        code, output = run(
            ["emerge", "--pretend", "--update", "--deep", "--with-bdeps=y", "@world"]
        )
        if code == 0:
            packages = parse_emerge_check(output)
            return {
                "status": "ok",
                "updates": len(packages),
                "packages": packages,
                "supportsMinimal": False,
                "note": "Uses local Portage metadata; sync repositories before checking for the latest updates.",
            }
    else:
        return {
            "status": "error",
            "error": "Package updates are supported here only for Fedora and Gentoo.",
        }

    return {"status": "error", "error": output.strip()}


def apply(minimal=False):
    family = distro_family()
    if family == "gentoo":
        if minimal:
            message = "Gentoo does not provide a generic security-only world update."
            return {
                "status": "error",
                "applied": False,
                "rebootNeeded": False,
                "results": [{"command": "emerge", "success": False, "output": message}],
            }
        commands = [
            [
                "pkexec", "emerge", "--ask=n", "--update", "--deep",
                "--with-bdeps=y", "--newuse", "@world",
            ]
        ]
    elif family == "fedora":
        upgrade = "upgrade-minimal" if minimal else "upgrade"
        commands = [
            ["pkexec", "dnf", upgrade, "-y"],
            ["pkexec", "dnf", "autoremove", "-y"],
            ["pkexec", "dnf", "clean", "all"],
        ]
    else:
        message = "Package updates are supported here only for Fedora and Gentoo."
        return {
            "status": "error",
            "applied": False,
            "rebootNeeded": False,
            "results": [{"command": "package manager", "success": False, "output": message}],
        }

    results = []

    for cmd in commands:
        code, output = run(cmd)

        results.append(
            {
                "command": " ".join(cmd),
                "success": code == 0,
                "output": output,
            }
        )

        if code != 0:
            break

    reboot_needed = family == "fedora" and shutil.which("needs-restarting") is not None

    if reboot_needed:
        code, _ = run(["needs-restarting", "-r"])
        reboot_needed = code == 1

    return {
        "status": "ok" if all(r["success"] for r in results) else "error",
        "applied": all(r["success"] for r in results),
        "rebootNeeded": reboot_needed,
        "results": results,
    }


def usage():
    print("usage:")
    print("  updater.py check")
    print("  updater.py apply")
    print("  updater.py apply-minimal")


def main():
    if len(sys.argv) != 2:
        usage()
        return 1

    command = sys.argv[1]

    if command == "check":
        print(json.dumps(check()))
        return 0

    if command == "apply":
        print(json.dumps(apply(False)))
        return 0

    if command == "apply-minimal":
        print(json.dumps(apply(True)))
        return 0

    usage()
    return 1


if __name__ == "__main__":
    sys.exit(main())
