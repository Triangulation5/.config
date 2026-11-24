#!/usr/bin/env python3
"""
Shell script validation & behavioral tests for silhouette-shell:
  - POSIX syntax check (`sh -n`) on every `.sh` file in the repository.
  - Shebang & executable-bit verification.
  - Wrapper fallback behavior (`useRustTools: false`, `SILHOUETTE_NO_NATIVE=1`).
  - `build.sh` skip behavior when Rust tools are disabled via flags.json.
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def iter_shell_scripts():
    for p in sorted(ROOT.rglob("*.sh")):
        if "target" in p.parts:
            continue
        yield p


class TestShellScripts(unittest.TestCase):
    def test_all_sh_syntax_valid(self):
        scripts = list(iter_shell_scripts())
        self.assertGreater(len(scripts), 0)
        failures = []
        for script in scripts:
            res = subprocess.run(
                ["sh", "-n", str(script)],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if res.returncode != 0:
                failures.append(f"{script.relative_to(ROOT)}: {res.stderr.strip()}")
        self.assertEqual(failures, [], f"Shell syntax errors:\n" + "\n".join(failures))

    def test_all_sh_have_shebang_and_executable(self):
        missing_shebang = []
        not_exec = []
        for script in iter_shell_scripts():
            first_line = script.read_text(encoding="utf-8").splitlines()[0] if script.stat().st_size else ""
            if not first_line.startswith("#!"):
                missing_shebang.append(str(script.relative_to(ROOT)))
            if not os.access(script, os.X_OK):
                not_exec.append(str(script.relative_to(ROOT)))
        self.assertEqual(missing_shebang, [], f"Scripts missing shebang: {missing_shebang}")
        self.assertEqual(not_exec, [], f"Non-executable scripts: {not_exec}")

    def test_sysmon_run_sh_falls_back_when_rust_disabled(self):
        with tempfile.TemporaryDirectory() as td:
            state = Path(td) / "silhouette"
            state.mkdir()
            (state / "flags.json").write_text(json.dumps({"useRustTools": False}))
            env = os.environ.copy()
            env["XDG_STATE_HOME"] = td
            res = subprocess.run(
                [str(ROOT / "utils" / "sysmon" / "run.sh"), "--once"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
                check=True,
            )
            lines = [l.strip() for l in res.stdout.splitlines() if l.strip()]
            self.assertGreaterEqual(len(lines), 2)
            self.assertTrue(lines[0].startswith("CPU "))
            self.assertTrue(lines[1].startswith("MEM "))

    def test_recording_run_sh_no_native_falls_back_to_python(self):
        env = os.environ.copy()
        env["SILHOUETTE_NO_NATIVE"] = "1"
        res = subprocess.run(
            [str(ROOT / "utils" / "recording" / "run.sh"), "--help"],
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )
        # portal_capture.py uses argparse, so --help exits 0 and mentions --output
        self.assertEqual(res.returncode, 0, f"stderr: {res.stderr}")
        self.assertIn("--output", res.stdout)

    def test_build_scripts_skip_when_rust_disabled(self):
        with tempfile.TemporaryDirectory() as td:
            state = Path(td) / "silhouette"
            state.mkdir()
            (state / "flags.json").write_text(json.dumps({"useRustTools": False}))
            env = os.environ.copy()
            env["XDG_STATE_HOME"] = td
            for rel in (
                "utils/sysmon/build.sh",
                "utils/watchers/build.sh",
                "utils/recording/build.sh",
            ):
                res = subprocess.run(
                    [str(ROOT / rel)],
                    capture_output=True,
                    text=True,
                    env=env,
                    timeout=5,
                )
                self.assertEqual(res.returncode, 0, f"{rel} failed: {res.stderr}")
                self.assertIn("disabled", res.stdout.lower(), f"{rel} did not skip: {res.stdout}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
