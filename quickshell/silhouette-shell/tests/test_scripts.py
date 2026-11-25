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
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_ROOT = ROOT.parent.parent


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

    def _rust_free_bin_dir(self, td: str) -> str:
        """Create a minimal PATH directory with POSIX/Python utilities but no cargo/rustc."""
        bin_dir = Path(td) / "no-rust-bin"
        bin_dir.mkdir()
        for tool in (
            "sh", "bash", "python3", "uname", "dirname", "basename", "env",
            "grep", "sed", "awk", "cat", "head", "tr", "cut", "sleep", "mkdir", "mv", "rm",
        ):
            found = shutil.which(tool)
            if found:
                os.symlink(found, bin_dir / tool)
        return str(bin_dir)

    def test_falls_back_cleanly_when_rust_not_installed(self):
        with tempfile.TemporaryDirectory() as td:
            home = Path(td) / "home"
            home.mkdir()
            no_rust_path = self._rust_free_bin_dir(td)
            env = {
                "HOME": str(home),
                "PATH": no_rust_path,
                "XDG_STATE_HOME": str(home / ".local" / "state"),
                "XDG_RUNTIME_DIR": str(Path(td) / "run"),
            }
            Path(env["XDG_RUNTIME_DIR"]).mkdir()

            # 1. build-rust-tools.sh --ensure exits 0 quietly when Rust is absent
            ensure = subprocess.run(
                [str(CONFIG_ROOT / "scripts" / "build-rust-tools.sh"), "--ensure"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
            )
            self.assertEqual(ensure.returncode, 0, f"stderr: {ensure.stderr}")

            # 2. sysmon/run.sh falls back to Python/POSIX sampler when Rust is absent
            sysmon = subprocess.run(
                [str(ROOT / "utils" / "sysmon" / "run.sh"), "--once"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
                check=True,
            )
            lines = [l.strip() for l in sysmon.stdout.splitlines() if l.strip()]
            self.assertTrue(lines[0].startswith("CPU "))
            self.assertTrue(lines[1].startswith("MEM "))

            # 3. watchers/run.sh exits 127 so QML services engage shell fallbacks
            watchers = subprocess.run(
                [str(ROOT / "utils" / "watchers" / "run.sh"), "downloads-probe"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
            )
            self.assertEqual(watchers.returncode, 127)

            # 4. recording/run.sh falls back to portal_capture.py when Rust is absent
            rec = subprocess.run(
                [str(ROOT / "utils" / "recording" / "run.sh"), "--help"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
            )
            self.assertEqual(rec.returncode, 0, f"stderr: {rec.stderr}")
            self.assertIn("--output", rec.stdout)

    def test_hypr_autostart_lua_dispatches_rust_vs_fallback(self):
        lua_bin = shutil.which("lua") or shutil.which("lua5.4") or shutil.which("luajit")
        if not lua_bin:
            self.skipTest("Lua interpreter not installed")

        autostart_lua = CONFIG_ROOT / "hypr" / "modules" / "autostart.lua"
        harness = (
            "local envs, cmds, hooks = {}, {}, {}\n"
            "hl = {\n"
            "  env = function(k, v) envs[k] = v end,\n"
            "  exec_cmd = function(c) table.insert(cmds, c) end,\n"
            "  on = function(ev, fn) hooks[ev] = fn end,\n"
            "}\n"
            "dofile(arg[1])\n"
            "if hooks['hyprland.start'] then hooks['hyprland.start']() end\n"
            "for k, v in pairs(envs) do print('ENV:' .. k .. '=' .. v) end\n"
            "for _, c in ipairs(cmds) do print('CMD:' .. c) end\n"
        )

        with tempfile.TemporaryDirectory() as td:
            harness_file = Path(td) / "harness.lua"
            harness_file.write_text(harness, encoding="utf-8")

            # Case A: No Rust anywhere -> fallback mode
            home_no_rust = Path(td) / "home-no-rust"
            home_no_rust.mkdir()
            no_rust_path = self._rust_free_bin_dir(td)
            res_no_rust = subprocess.run(
                [lua_bin, str(harness_file), str(autostart_lua)],
                capture_output=True,
                text=True,
                env={"HOME": str(home_no_rust), "PATH": no_rust_path},
                timeout=5,
                check=True,
            )
            self.assertIn("ENV:SILHOUETTE_NO_NATIVE=1", res_no_rust.stdout)
            self.assertIn("watchdog-fallback.sh silhouette-shell", res_no_rust.stdout)
            self.assertNotIn("build-rust-tools.sh", res_no_rust.stdout)

            # Case B: Rust installed in ~/.cargo/bin (even when missing from PATH) -> Rust mode
            home_rust = Path(td) / "home-rust"
            cargo_bin = home_rust / ".cargo" / "bin"
            cargo_bin.mkdir(parents=True)
            (cargo_bin / "cargo").write_text("#!/bin/sh\nexit 0\n")
            res_rust = subprocess.run(
                [lua_bin, str(harness_file), str(autostart_lua)],
                capture_output=True,
                text=True,
                env={"HOME": str(home_rust), "PATH": no_rust_path},
                timeout=5,
                check=True,
            )
            self.assertNotIn("ENV:SILHOUETTE_NO_NATIVE=1", res_rust.stdout)
            self.assertIn(f"ENV:PATH={cargo_bin}:", res_rust.stdout)
            self.assertIn("build-rust-tools.sh --ensure", res_rust.stdout)
            self.assertIn("watchdog.sh silhouette-shell", res_rust.stdout)

            # Case C: Rust installed, but useRustTools: false in flags.json -> fallback supervisor
            state_dir = home_rust / ".local" / "state" / "silhouette"
            state_dir.mkdir(parents=True)
            (state_dir / "flags.json").write_text(json.dumps({"useRustTools": False}))
            res_disabled = subprocess.run(
                [lua_bin, str(harness_file), str(autostart_lua)],
                capture_output=True,
                text=True,
                env={"HOME": str(home_rust), "PATH": no_rust_path},
                timeout=5,
                check=True,
            )
            self.assertNotIn("build-rust-tools.sh", res_disabled.stdout)
            self.assertIn("watchdog-fallback.sh silhouette-shell", res_disabled.stdout)

            # Case D: Rust installed, useRustTools enabled, and silhouette-tools binary present -> direct Rust autostart
            (state_dir / "flags.json").write_text(json.dumps({"useRustTools": True}))
            bin_dir = home_rust / ".config" / "scripts" / "bin"
            bin_dir.mkdir(parents=True)
            (bin_dir / "silhouette-tools").write_text("#!/bin/sh\nexit 0\n")
            res_warm = subprocess.run(
                [lua_bin, str(harness_file), str(autostart_lua)],
                capture_output=True,
                text=True,
                env={"HOME": str(home_rust), "PATH": no_rust_path},
                timeout=5,
                check=True,
            )
            self.assertIn("silhouette-tools session-start", res_warm.stdout)
            self.assertIn("silhouette-tools awww-daemon start", res_warm.stdout)
            self.assertIn("silhouette-tools cliphist-watch", res_warm.stdout)
            self.assertIn("silhouette-tools watchdog silhouette-shell", res_warm.stdout)

    def test_rust_and_shell_parity_for_desktop_scripts(self):
        rust_bin = CONFIG_ROOT / "scripts" / "bin" / "silhouette-tools"
        if not rust_bin.is_file():
            self.skipTest("silhouette-tools binary not built")

        for force_fallback in (False, True):
            with self.subTest(fallback=force_fallback), tempfile.TemporaryDirectory() as td:
                td_path = Path(td)
                home = td_path / "home"
                state = home / ".local" / "state"
                cache = home / ".cache"
                data = home / ".local" / "share"
                for d in (home, state, cache, data):
                    d.mkdir(parents=True)

                # Seed old `ricelin` state to verify `migrate-state.sh` in both modes
                (state / "ricelin").mkdir()
                (state / "ricelin" / "flags.json").write_text('{"useRustTools":true}\n')
                (home / ".config" / "hypr" / "modules").mkdir(parents=True)
                (home / ".config" / "hypr" / "modules" / "style.lua").write_text("return { dwmStyle = true }\n")

                fake_bin = td_path / "fake-bin"
                fake_bin.mkdir()
                (fake_bin / "kitty").write_text("#!/bin/sh\nexit 0\n")
                (fake_bin / "kitty").chmod(0o755)

                env = os.environ.copy()
                env["HOME"] = str(home)
                env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"
                env["XDG_STATE_HOME"] = str(state)
                env["XDG_CACHE_HOME"] = str(cache)
                env["XDG_DATA_HOME"] = str(data)
                if force_fallback:
                    env["SILHOUETTE_NO_NATIVE"] = "1"

                subprocess.run(
                    ["sh", str(CONFIG_ROOT / "scripts" / "migrate-state.sh")],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=env,
                    timeout=5,
                    check=True,
                )
                self.assertTrue((state / "silhouette" / "flags.json").is_file())
                self.assertFalse((state / "ricelin").exists())

                subprocess.run(
                    ["bash", str(CONFIG_ROOT / "scripts" / "update-kitty-opacity.sh")],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=env,
                    timeout=5,
                    check=True,
                )
                self.assertEqual(
                    (cache / "silhouette" / "kitty-opacity").read_text().strip(),
                    "background_opacity 1.00",
                )

                if shutil.which("magick"):
                    src_pic = td_path / "wall.png"
                    subprocess.run(
                        ["magick", "-size", "320x200", "xc:darkslateblue", str(src_pic)],
                        check=True,
                        timeout=5,
                    )
                    subprocess.run(
                        ["bash", str(CONFIG_ROOT / "scripts" / "lock-wallpaper.sh"), str(src_pic)],
                        env=env,
                        timeout=5,
                        check=True,
                    )
                    self.assertTrue((state / "silhouette-lock-wallpaper.jpg").is_file())
                    self.assertGreater((state / "silhouette-lock-wallpaper.jpg").stat().st_size, 100)
                    link_lines = (state / "silhouette-lock-wallpaper").read_text().splitlines()
                    self.assertEqual(link_lines[1], str(src_pic))


if __name__ == "__main__":
    unittest.main(verbosity=2)
