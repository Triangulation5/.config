#!/usr/bin/env python3

import json
import shutil
import subprocess
import sys


def run(cmd):
    """Run a command and capture stdout/stderr."""
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.returncode, result.stdout


def parse_check(output):
    """
    Extract package names from `dnf check-update`.

    DNF exits:
      0 = no updates
    100 = updates available
      1 = error
    """

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


def check():
    code, output = run(["dnf", "check-update"])

    if code == 0:
        return {
            "status": "ok",
            "updates": 0,
            "packages": [],
        }

    if code == 100:
        packages = parse_check(output)

        return {
            "status": "ok",
            "updates": len(packages),
            "packages": packages,
        }

    return {
        "status": "error",
        "error": output.strip(),
    }


def apply(minimal=False):
    upgrade = "upgrade-minimal" if minimal else "upgrade"

    commands = [
        ["pkexec", "dnf", upgrade, "-y"],
        ["pkexec", "dnf", "autoremove", "-y"],
        ["pkexec", "dnf", "clean", "all"],
    ]

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

    reboot_needed = shutil.which("needs-restarting") is not None

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
