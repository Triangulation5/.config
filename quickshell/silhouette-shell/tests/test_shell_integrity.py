#!/usr/bin/env python3
"""
Static & contract integrity tests for silhouette-shell QML & services:
  1. QML linter (`utils/lint_qml.py`) passes cleanly across the whole tree.
  2. Every `qmldir` entry resolves to an existing file on disk.
  3. `pragma Singleton` <-> `qmldir` `singleton` declaration parity.
  4. Every relative QML `import "..."` resolves to an existing file or directory.
  5. Every `Qt.resolvedUrl("...utils/...")` target exists (and `.sh` runners are executable).
  6. Every `utils/watchers/run.sh` subcommand invoked in QML exists in `utils/watchers/main.rs`.
  7. Every `.qml` file is valid UTF-8 and non-empty.
"""

import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def iter_qml_files():
    for p in sorted(ROOT.rglob("*.qml")):
        if "target" in p.parts:
            continue
        yield p


def iter_qmldir_files():
    for p in sorted(ROOT.rglob("qmldir")):
        if "target" in p.parts:
            continue
        yield p


class TestShellIntegrity(unittest.TestCase):
    def test_qml_lint_clean(self):
        res = subprocess.run(
            ["python3", str(ROOT / "utils" / "lint_qml.py")],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(res.returncode, 0, f"lint_qml.py failed:\n{res.stdout}\n{res.stderr}")

    def test_all_qml_files_valid_utf8_and_non_empty(self):
        qmls = list(iter_qml_files())
        self.assertGreater(len(qmls), 50)
        bad = []
        for qml in qmls:
            try:
                text = qml.read_text(encoding="utf-8")
                if not text.strip():
                    bad.append(f"{qml.relative_to(ROOT)}: empty")
            except UnicodeDecodeError as exc:
                bad.append(f"{qml.relative_to(ROOT)}: {exc}")
        self.assertEqual(bad, [], f"Invalid QML files: {bad}")

    def test_qmldir_entries_exist_and_singleton_parity(self):
        qmldirs = list(iter_qmldir_files())
        self.assertGreater(len(qmldirs), 0)
        missing = []
        parity_errors = []
        for qd in qmldirs:
            declared_singletons = set()
            for raw in qd.read_text(encoding="utf-8").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or line.startswith("module "):
                    continue
                parts = line.split()
                is_singleton = parts[0] == "singleton"
                fname = parts[-1]
                if fname.endswith((".qml", ".js")):
                    target = qd.parent / fname
                    if not target.is_file():
                        missing.append(f"{qd.relative_to(ROOT)} -> {fname}")
                        continue
                    if is_singleton and fname.endswith(".qml"):
                        declared_singletons.add(fname)
                        text = target.read_text(encoding="utf-8")
                        if not re.search(r"^\s*pragma\s+Singleton\b", text, re.MULTILINE):
                            parity_errors.append(
                                f"{target.relative_to(ROOT)}: declared singleton in qmldir but missing `pragma Singleton`"
                            )
            # Check reverse: any QML in this dir with `pragma Singleton` must be listed as singleton
            for sibling in sorted(qd.parent.glob("*.qml")):
                text = sibling.read_text(encoding="utf-8")
                if re.search(r"^\s*pragma\s+Singleton\b", text, re.MULTILINE):
                    if sibling.name not in declared_singletons:
                        parity_errors.append(
                            f"{sibling.relative_to(ROOT)}: has `pragma Singleton` but not declared singleton in {qd.relative_to(ROOT)}"
                        )

        self.assertEqual(missing, [], f"Dangling qmldir entries: {missing}")
        self.assertEqual(parity_errors, [], f"Singleton parity errors:\n" + "\n".join(parity_errors))

    def test_qml_relative_imports_resolve(self):
        imp_pat = re.compile(r'^\s*import\s+"([^"]+)"', re.MULTILINE)
        broken = []
        for qml in iter_qml_files():
            text = qml.read_text(encoding="utf-8")
            for m in imp_pat.finditer(text):
                rel = m.group(1)
                target = (qml.parent / rel).resolve()
                if not target.exists():
                    broken.append(f"{qml.relative_to(ROOT)}: import \"{rel}\"")
        self.assertEqual(broken, [], f"Broken relative QML imports:\n" + "\n".join(broken))

    def test_resolved_utils_urls_exist_and_scripts_executable(self):
        pat = re.compile(r'Qt\.resolvedUrl\("([^"]*utils/[^"]+)"\)')
        missing = []
        not_exec = []
        for qml in iter_qml_files():
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
        main_body = main_rs.split("fn main()", 1)[1]
        registered = set(re.findall(r'"([a-z0-9-]+)"\s*=>', main_body))
        self.assertGreater(len(registered), 5)

        invoke_pat = re.compile(r'watcherRunner\s*,\s*"([a-z0-9-]+)"')
        unknown = []
        used = set()
        for qml in iter_qml_files():
            text = qml.read_text(encoding="utf-8")
            for m in invoke_pat.finditer(text):
                cmd = m.group(1)
                used.add(cmd)
                if cmd not in registered:
                    unknown.append(f"{qml.relative_to(ROOT)}: {cmd}")
        self.assertEqual(unknown, [], f"QML invokes unknown watcher subcommands: {unknown}")
        self.assertGreater(len(used), 8)

    def test_rust_files_under_500_lines(self):
        oversized = []
        for rs in sorted((ROOT / "utils").rglob("*.rs")):
            if "target" in rs.parts:
                continue
            lines = len(rs.read_text(encoding="utf-8").splitlines())
            if lines > 500:
                oversized.append(f"{rs.relative_to(ROOT)}: {lines} lines")
        self.assertEqual(oversized, [], f"Rust files over 500 lines:\n" + "\n".join(oversized))


if __name__ == "__main__":
    unittest.main(verbosity=2)
