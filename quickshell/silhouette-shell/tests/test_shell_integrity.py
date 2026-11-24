#!/usr/bin/env python3
"""
Static & contract integrity tests for silhouette-shell:
  1. QML linter (`utils/lint_qml.py`) passes cleanly.
  2. Every `qmldir` entry resolves to an existing file on disk.
  3. Every `Qt.resolvedUrl("...utils/...")` target exists (and `.sh` runners are executable).
  4. Every `utils/watchers/run.sh` subcommand invoked in QML exists in `utils/watchers/main.rs`.
  5. `utils/backup.py` create -> list -> restore -> remove round-trip against a scratch tree.
"""

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class TestShellIntegrity(unittest.TestCase):
    def test_qml_lint_clean(self):
        res = subprocess.run(
            ["python3", str(ROOT / "utils" / "lint_qml.py")],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(res.returncode, 0, f"lint_qml.py failed:\n{res.stdout}\n{res.stderr}")

    def test_qmldir_entries_exist(self):
        qmldirs = sorted(ROOT.rglob("qmldir"))
        self.assertGreater(len(qmldirs), 0)
        missing = []
        for qd in qmldirs:
            if "target" in qd.parts:
                continue
            for raw in qd.read_text(encoding="utf-8").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or line.startswith("module "):
                    continue
                parts = line.split()
                # Formats: [singleton] TypeName Version File.qml
                fname = parts[-1]
                if fname.endswith((".qml", ".js")):
                    if not (qd.parent / fname).is_file():
                        missing.append(f"{qd.relative_to(ROOT)} -> {fname}")
        self.assertEqual(missing, [], f"Dangling qmldir entries: {missing}")

    def test_resolved_utils_urls_exist_and_scripts_executable(self):
        pat = re.compile(r'Qt\.resolvedUrl\("([^"]*utils/[^"]+)"\)')
        missing = []
        not_exec = []
        for qml in sorted(ROOT.rglob("*.qml")):
            if "target" in qml.parts:
                continue
            text = qml.read_text(encoding="utf-8")
            for m in pat.finditer(text):
                rel = m.group(1)
                resolved = (qml.parent / rel).resolve()
                if not resolved.is_file():
                    missing.append(f"{qml.relative_to(ROOT)}: {rel}")
                elif resolved.suffix == ".sh" and not os.access(resolved, os.X_OK):
                    not_exec.append(str(resolved.relative_to(ROOT)))
        self.assertEqual(missing, [], f"Broken Qt.resolvedUrl utils paths: {missing}")
        self.assertEqual(not_exec, [], f"Non-executable .sh runners: {not_exec}")

    def test_watcher_subcommands_match_rust_dispatch(self):
        main_rs = (ROOT / "utils" / "watchers" / "main.rs").read_text(encoding="utf-8")
        # Extract `"subcmd" =>` arms inside main()
        main_body = main_rs.split("fn main()", 1)[1]
        registered = set(re.findall(r'"([a-z0-9-]+)"\s*=>', main_body))
        self.assertGreater(len(registered), 5)

        invoke_pat = re.compile(r'watcherRunner\s*,\s*"([a-z0-9-]+)"')
        unknown = []
        used = set()
        for qml in sorted(ROOT.rglob("*.qml")):
            if "target" in qml.parts:
                continue
            text = qml.read_text(encoding="utf-8")
            for m in invoke_pat.finditer(text):
                cmd = m.group(1)
                used.add(cmd)
                if cmd not in registered:
                    unknown.append(f"{qml.relative_to(ROOT)}: {cmd}")
        self.assertEqual(unknown, [], f"QML invokes unknown watcher subcommands: {unknown}")
        self.assertGreater(len(used), 8)

    def test_backup_round_trip(self):
        with tempfile.TemporaryDirectory() as td:
            shell = Path(td) / "shell"
            state = Path(td) / "state"
            bdir = Path(td) / "backups"
            shell.mkdir()
            state.mkdir()
            bdir.mkdir()
            (shell / "shell.qml").write_text("// hello\n")
            (state / "flags.json").write_text('{"useRustTools": true}\n')

            env = os.environ.copy()
            env["SILHOUETTE_FORCE_PYTHON"] = "1"
            base = [
                "python3",
                str(ROOT / "utils" / "backup.py"),
                "--shell",
                str(shell),
                "--state",
                str(state),
                "--dir",
                str(bdir),
            ]

            c = json.loads(subprocess.check_output(base + ["create"], text=True, env=env))
            self.assertEqual(c["status"], "ok")
            name = c["name"]

            ls = json.loads(subprocess.check_output(base + ["list"], text=True, env=env))
            self.assertEqual(ls["status"], "ok")
            self.assertEqual([b["name"] for b in ls["backups"]], [name])

            # Mutate shell file and restore
            (shell / "shell.qml").write_text("// mutated\n")
            r = json.loads(subprocess.check_output(base + ["restore", name], text=True, env=env))
            self.assertEqual(r["status"], "ok")
            self.assertEqual((shell / "shell.qml").read_text(), "// hello\n")

            rm = json.loads(subprocess.check_output(base + ["remove", name], text=True, env=env))
            self.assertEqual(rm["status"], "ok")
            ls2 = json.loads(subprocess.check_output(base + ["list"], text=True, env=env))
            self.assertEqual(ls2["backups"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
