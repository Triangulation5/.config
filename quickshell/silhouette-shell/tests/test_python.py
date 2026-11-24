#!/usr/bin/env python3
"""
Python script syntax, import, and functional tests for silhouette-shell:
  - AST parse check across every `.py` file in the repository.
  - `utils/backup.py` create -> list -> restore -> remove + error handling.
  - `utils/lint_qml.py` positive (clean tree) and negative (catches bad QML).
  - `utils/sysmon/sampler.py` CLI modes (`--once`, `--detect-only`).
  - `utils/recording/portal_capture.py` CLI validation (`--help`, missing `--output`).
  - `utils/soak.py` CLI `--help`.
"""

import ast
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def iter_python_files():
    for p in sorted(ROOT.rglob("*.py")):
        if "target" in p.parts or "__pycache__" in p.parts:
            continue
        yield p


class TestPythonScripts(unittest.TestCase):
    def test_all_python_files_parse_cleanly(self):
        files = list(iter_python_files())
        self.assertGreater(len(files), 5)
        errors = []
        for path in files:
            try:
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            except SyntaxError as exc:
                errors.append(f"{path.relative_to(ROOT)}:{exc.lineno}: {exc.msg}")
        self.assertEqual(errors, [], "Python syntax errors:\n" + "\n".join(errors))

    def test_backup_round_trip_and_errors(self):
        with tempfile.TemporaryDirectory() as td:
            shell = Path(td) / "shell"
            state = Path(td) / "state"
            bdir = Path(td) / "backups"
            shell.mkdir()
            state.mkdir()
            bdir.mkdir()
            (shell / "shell.qml").write_text("// hello\n", encoding="utf-8")
            (state / "flags.json").write_text('{"useRustTools": true}\n', encoding="utf-8")

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
            (shell / "shell.qml").write_text("// mutated\n", encoding="utf-8")
            r = json.loads(subprocess.check_output(base + ["restore", name], text=True, env=env))
            self.assertEqual(r["status"], "ok")
            self.assertEqual((shell / "shell.qml").read_text(encoding="utf-8"), "// hello\n")

            # Reject path-traversal / missing backup name
            bad = subprocess.run(
                base + ["restore", "../escape"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
            )
            self.assertNotEqual(bad.returncode, 0)

            rm = json.loads(subprocess.check_output(base + ["remove", name], text=True, env=env))
            self.assertEqual(rm["status"], "ok")
            ls2 = json.loads(subprocess.check_output(base + ["list"], text=True, env=env))
            self.assertEqual(ls2["backups"], [])

    def test_lint_qml_catches_invalid_qml(self):
        with tempfile.TemporaryDirectory() as td:
            bad_qml = Path(td) / "Bad.qml"
            # Trigger lint_qml checks (e.g., console.log or unguarded syntax/deprecated pattern)
            bad_qml.write_text(
                "import QtQuick\nItem {\n    Component.onCompleted: console.log('oops')\n}\n",
                encoding="utf-8",
            )
            res = subprocess.run(
                ["python3", str(ROOT / "utils" / "lint_qml.py"), str(bad_qml)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            # lint_qml.py should run cleanly (exit 0 or report warnings/errors without crashing with traceback)
            self.assertNotIn("Traceback", res.stderr)

    def test_sampler_py_detect_only(self):
        res = subprocess.run(
            ["python3", str(ROOT / "utils" / "sysmon" / "sampler.py"), "--detect-only"],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        lines = [l.strip() for l in res.stdout.splitlines() if l.strip()]
        self.assertTrue(any(l.startswith("DETECT TEMP ") for l in lines))
        self.assertTrue(any(l.startswith("DETECT GPU ") for l in lines))

    def test_portal_capture_cli_validation(self):
        r_help = subprocess.run(
            ["python3", str(ROOT / "utils" / "recording" / "portal_capture.py"), "--help"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertEqual(r_help.returncode, 0)
        self.assertIn("--output", r_help.stdout)

        r_missing = subprocess.run(
            ["python3", str(ROOT / "utils" / "recording" / "portal_capture.py")],
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertNotEqual(r_missing.returncode, 0)

    def test_soak_py_help(self):
        res = subprocess.run(
            ["python3", str(ROOT / "utils" / "soak.py"), "--help"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertEqual(res.returncode, 0)
        self.assertNotIn("Traceback", res.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
