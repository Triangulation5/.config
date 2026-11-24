#!/usr/bin/env python3
"""
End-to-end integration tests for silhouette-shell's native Rust tools and
Python/POSIX fallback ladders (sysmon_sampler, silhouette_watchers, framepump).
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYSMON_DIR = ROOT / "utils" / "sysmon"
WATCHERS_DIR = ROOT / "utils" / "watchers"
REC_DIR = ROOT / "utils" / "recording"


def run_head(cmd, lines, timeout=5, env=None):
    """Spawn a streaming command, read `lines` lines from stdout, then terminate."""
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    out = []
    try:
        assert proc.stdout is not None
        deadline = time.monotonic() + timeout
        while len(out) < lines and time.monotonic() < deadline:
            line = proc.stdout.readline()
            if not line:
                break
            out.append(line.strip())
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        if proc.stdout:
            proc.stdout.close()
        if proc.stderr:
            proc.stderr.close()
    return out


class TestSysmonSampler(unittest.TestCase):
    def _assert_once_protocol(self, cmd):
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5, check=True)
        lines = [l.strip() for l in res.stdout.splitlines() if l.strip()]
        self.assertGreaterEqual(len(lines), 2, f"unexpected output from {cmd}: {lines}")
        cpu = lines[0].split()
        mem = lines[1].split()
        self.assertEqual(cpu[0], "CPU")
        self.assertGreater(int(cpu[1]), 0)
        self.assertEqual(mem[0], "MEM")
        self.assertGreater(int(mem[1]), 0)

    def test_once_parity_across_tiers(self):
        self._assert_once_protocol([str(SYSMON_DIR / "sysmon_sampler"), "--once"])
        self._assert_once_protocol(["python3", str(SYSMON_DIR / "sampler.py"), "--once"])
        self._assert_once_protocol(["sh", str(SYSMON_DIR / "sampler.sh"), "--once"])

    def test_vitals_only_streaming_parity(self):
        for cmd in (
            [str(SYSMON_DIR / "sysmon_sampler"), "--vitals-only", "--interval", "200"],
            ["python3", str(SYSMON_DIR / "sampler.py"), "--vitals-only", "--interval", "200"],
        ):
            lines = run_head(cmd, 4)
            self.assertEqual(len(lines), 4, f"short stream from {cmd}: {lines}")
            self.assertTrue(lines[0].startswith("CPU "))
            self.assertTrue(lines[1].startswith("MEM "))
            self.assertTrue(lines[2].startswith("CPU "))
            self.assertTrue(lines[3].startswith("MEM "))

    def test_watch_pid_rss_parity(self):
        pid = str(os.getpid())
        for cmd in (
            [str(SYSMON_DIR / "sysmon_sampler"), "--watch-pid", pid, "--interval", "500"],
            ["python3", str(SYSMON_DIR / "sampler.py"), "--watch-pid", pid, "--interval", "500"],
            ["sh", str(SYSMON_DIR / "sampler.sh"), "--watch-pid", pid, "--interval", "1000"],
        ):
            lines = run_head(cmd, 1)
            self.assertEqual(len(lines), 1, f"no RSS line from {cmd}")
            parts = lines[0].split()
            self.assertEqual(parts[0], "RSS")
            self.assertGreaterEqual(int(parts[1]), 1)

    def test_detect_only(self):
        res = subprocess.run(
            [str(SYSMON_DIR / "sysmon_sampler"), "--detect-only"],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        lines = [l.strip() for l in res.stdout.splitlines() if l.strip()]
        self.assertTrue(any(l.startswith("DETECT TEMP ") for l in lines))
        self.assertTrue(any(l.startswith("DETECT GPU ") for l in lines))


class TestWatchers(unittest.TestCase):
    RUNNER = str(WATCHERS_DIR / "run.sh")

    def test_flags_disable_returns_127(self):
        with tempfile.TemporaryDirectory() as td:
            state = Path(td) / "silhouette"
            state.mkdir()
            (state / "flags.json").write_text(json.dumps({"useRustTools": False}))
            env = os.environ.copy()
            env["XDG_STATE_HOME"] = td
            res = subprocess.run(
                [self.RUNNER, "downloads-probe"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
            )
            self.assertEqual(res.returncode, 127)

    def test_downloads_probe_picks_newest_profile(self):
        with tempfile.TemporaryDirectory() as td:
            p1 = Path(td) / ".mozilla" / "firefox" / "old.default"
            p2 = Path(td) / ".config" / "mozilla" / "firefox" / "new.default"
            p1.mkdir(parents=True)
            p2.mkdir(parents=True)
            f1 = p1 / "downloads.json"
            f2 = p2 / "downloads.json"
            f1.write_text("{}")
            f2.write_text("{}")
            os.utime(f1, (1000, 1000))
            os.utime(f2, (2000, 2000))
            env = os.environ.copy()
            env["HOME"] = td
            res = subprocess.run(
                [self.RUNNER, "downloads-probe"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
                check=True,
            )
            self.assertEqual(res.stdout.strip(), str(f2))

    def test_stat_watch_tracks_file_growth(self):
        with tempfile.TemporaryDirectory() as td:
            target = Path(td) / "dl.part"
            target.write_bytes(b"a" * 100)
            proc = subprocess.Popen(
                [self.RUNNER, "stat-watch", str(target), "--interval", "200"],
                stdout=subprocess.PIPE,
                text=True,
            )
            try:
                assert proc.stdout is not None
                first = int(proc.stdout.readline().strip())
                self.assertEqual(first, 100)
                target.write_bytes(b"a" * 512)
                seen_grown = False
                for _ in range(10):
                    val = int(proc.stdout.readline().strip())
                    if val == 512:
                        seen_grown = True
                        break
                self.assertTrue(seen_grown)
            finally:
                proc.terminate()
                proc.wait(timeout=2)
                if proc.stdout:
                    proc.stdout.close()

    def test_file_wait_inotify(self):
        with tempfile.TemporaryDirectory() as td:
            sentinel = Path(td) / "clip.mp4.capturing"

            def create_later():
                time.sleep(0.15)
                sentinel.write_text("1234\n")

            t = threading.Thread(target=create_later, daemon=True)
            t.start()
            res = subprocess.run(
                [self.RUNNER, "file-wait", str(sentinel)],
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
            self.assertEqual(res.stdout.strip(), "yes")

    def test_proc_watch_modes(self):
        for mode in ("rec", "claude"):
            lines = run_head([self.RUNNER, "proc-watch", "--mode", mode, "--interval", "250"], 1)
            self.assertEqual(len(lines), 1)
            parts = lines[0].split()
            self.assertEqual(parts[0], "COUNT")
            self.assertGreaterEqual(int(parts[1]), 0)

    def test_thumbs_walls_generates_prunes_and_indexes(self):
        if not (shutil.which("magick") or shutil.which("convert")):
            self.skipTest("ImageMagick not installed")
        with tempfile.TemporaryDirectory() as td:
            wp = Path(td) / "wp"
            th = Path(td) / "thumbs"
            st = Path(td) / "state"
            wp.mkdir()
            th.mkdir()
            img = wp / "blue.png"
            subprocess.run(
                [shutil.which("magick") or "convert", "-size", "640x480", "xc:navy", str(img)],
                check=True,
            )
            stale = th / "deleted.png.png"
            stale.write_bytes(b"stale")
            st.write_text(str(img) + "\n")

            res = subprocess.run(
                [self.RUNNER, "thumbs-walls", str(wp), str(th), str(st)],
                capture_output=True,
                text=True,
                timeout=10,
                check=True,
            )
            data = json.loads(res.stdout)
            self.assertEqual(data["current"], str(img))
            self.assertEqual(len(data["entries"]), 1)
            self.assertEqual(data["entries"][0]["name"], "blue.png")
            self.assertTrue((th / "blue.png.png").is_file())
            self.assertFalse(stale.exists(), "stale thumbnail should be pruned")

    def test_thumbs_rec_filters_and_truncates(self):
        with tempfile.TemporaryDirectory() as td:
            out_dir = Path(td) / "rec"
            th_dir = Path(td) / "thumbs"
            out_dir.mkdir()
            th_dir.mkdir()
            for idx, mtime in ((1, 1000), (2, 2000), (3, 3000)):
                f = out_dir / f"recording_0{idx}.mp4"
                f.write_bytes(b"")
                os.utime(f, (mtime, mtime))
                # Pre-create thumb so ffmpeg isn't invoked on empty dummy files
                (th_dir / f"recording_0{idx}.jpg").write_bytes(b"jpg")

            res = subprocess.run(
                [self.RUNNER, "thumbs-rec", str(out_dir), str(th_dir), "1", "1500"],
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
            data = json.loads(res.stdout)
            self.assertEqual(len(data), 1)
            self.assertEqual(data[0]["name"], "recording_03.mp4")

    def test_emoji_match_ranking(self):
        emojis_js = ROOT / "utils" / "launcher" / "emojis.js"
        res = subprocess.run(
            [self.RUNNER, "emoji-match", str(emojis_js)],
            input="1\tfire\n2\trocket\n",
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        lines = [json.loads(l) for l in res.stdout.splitlines() if l.strip()]
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0]["seq"], 1)
        self.assertGreater(len(lines[0]["indices"]), 0)
        self.assertEqual(lines[1]["seq"], 2)
        self.assertGreater(len(lines[1]["indices"]), 0)

    def test_cursor_themes_discovery(self):
        with tempfile.TemporaryDirectory() as td:
            t1 = Path(td) / ".icons" / "AlphaCursor" / "cursors"
            t2 = Path(td) / "xdg" / "icons" / "BetaCursor" / "cursors"
            t3 = Path(td) / ".icons" / "NotACursorTheme"
            t1.mkdir(parents=True)
            t2.mkdir(parents=True)
            t3.mkdir(parents=True)
            env = os.environ.copy()
            env["HOME"] = td
            env["XDG_DATA_DIRS"] = str(Path(td) / "xdg")
            res = subprocess.run(
                [self.RUNNER, "cursor-themes"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
                check=True,
            )
            found = set(res.stdout.splitlines())
            self.assertIn("AlphaCursor", found)
            self.assertIn("BetaCursor", found)
            self.assertNotIn("NotACursorTheme", found)

    def test_write_file_atomic(self):
        with tempfile.TemporaryDirectory() as td:
            dst = Path(td) / "nested" / "dir" / "val"
            subprocess.run(
                [self.RUNNER, "write-file", str(dst), "75"],
                check=True,
                timeout=5,
            )
            self.assertEqual(dst.read_text(), "75\n")

    def test_unknown_subcommand_exits_2(self):
        res = subprocess.run(
            [self.RUNNER, "definitely-not-a-subcommand"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertEqual(res.returncode, 2)

    def test_net_local_ip_format(self):
        res = subprocess.run(
            [self.RUNNER, "net-local-ip"],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        out = res.stdout.strip()
        if out:
            parts = out.split(".")
            self.assertEqual(len(parts), 4, f"invalid IPv4: {out}")
            for p in parts:
                self.assertTrue(0 <= int(p) <= 255)


class TestFramepump(unittest.TestCase):
    def test_cli_validation(self):
        bin_path = str(REC_DIR / "framepump")
        r1 = subprocess.run([bin_path], capture_output=True, text=True, timeout=5)
        self.assertEqual(r1.returncode, 1)
        r2 = subprocess.run([bin_path, "--portal"], capture_output=True, text=True, timeout=5)
        self.assertEqual(r2.returncode, 2)

    def test_frame_alignment_and_rate_probe(self):
        """Feed 5.5 synthetic frames to framepump; verify exactly 5 whole frames reach consumer."""
        bin_path = str(REC_DIR / "framepump")
        frame_bytes = 1024
        payload = b"A" * (frame_bytes * 5 + 333)
        with tempfile.TemporaryDirectory() as td:
            out_file = Path(td) / "captured.raw"
            err_file = Path(td) / "ff.err"
            # Use a lightweight /bin/sh consumer (sub-ms startup) that ignores SIGINT
            # while draining stdin to EOF, matching ffmpeg's trailer-flush behavior.
            proc = subprocess.Popen(
                [
                    bin_path,
                    "--frame-bytes",
                    str(frame_bytes),
                    "--fps",
                    "300",
                    "--probe-seconds",
                    "0.05",
                    "--stderr-file",
                    str(err_file),
                    "--",
                    "sh",
                    "-c",
                    'trap "" INT; cat > "$2"',
                    "--",
                    "--rate-placeholder--",
                    str(out_file),
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            assert proc.stdin is not None and proc.stdout is not None
            proc.stdin.write(payload)
            proc.stdin.flush()
            # Wait for framepump to finish probing, spawn the consumer, and print `rate <float>`
            rate_line = proc.stdout.readline().decode(errors="replace").strip()
            time.sleep(0.05)
            proc.stdin.close()
            _, stderr_b = proc.communicate(timeout=10)
            self.assertEqual(proc.returncode, 0, f"stderr: {stderr_b.decode(errors='replace')}")
            self.assertTrue(rate_line.startswith("rate "), f"unexpected stdout: {rate_line}")
            rate_val = float(rate_line.split()[1])
            self.assertGreaterEqual(rate_val, 0.5)
            self.assertEqual(len(out_file.read_bytes()), frame_bytes * 5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
