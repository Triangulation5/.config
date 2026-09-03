#!/usr/bin/env python3
"""
soak.py — memory soak for the silhouette-shell quickshell config.

Measures the running shell's RSS (VmRSS / RssAnon) across a workload:

  restart   optionally restart the shell first (pkill + relaunch, exactly what
            hypr/scripts/reload.sh does) — never while the session is locked
  stress    open + close every pill surface once, sampling RSS at each step
  reclaim   hold still past the 12s idle reclaimer + 10s cleaner tick and
            confirm closed surfaces actually return memory
  quiet     idle soak with a least-squares trend (MB/min) to catch slow leaks

It is deliberately safe around the lock: it refuses to restart while the lock
is up (or waits with --wait-unlock), never kills anything in --lock mode, and
always relaunches the shell at exit if it finds none running.

Usage:
  soak.py [--no-restart] [--cycles N] [--hold SEC] [--quiet SEC]
          [--surfaces "a b c"] [--lock [SEC]] [--wait-unlock] [--json]

Env knobs:
  QS_IPC       ipc call command template (default: qs -c silhouette-shell ipc call)
  SHELL_PATH   project path (default: ~/.config/quickshell/silhouette-shell/)

Requires python3, a running Hyprland session, and the shell running as
`qs -p <path>` (or started from <path>). Read-only otherwise.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
SHELL_PATH = os.environ.get("SHELL_PATH", os.path.join(HOME, ".config/quickshell/silhouette-shell/"))
IPC = os.environ.get("QS_IPC", "qs -c silhouette-shell ipc call").split()
LOG_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")), "ricelin")

# Surfaces whose open has real side effects or needs external state — excluded
# from the default cycle. Recorder/updates/polkit/call need live conditions.
RISKY = {"recorder", "updates", "polkit", "call", "quickRecord"}
DEFAULT_SURFACES = (
    "calendar launcher clipboard wallpaper settings keybinds workspaces stash "
    "spaceapps appearance display input look idlelock animation fontpicker "
    "sysmon battery power mixer link weather timer media"
).split()

COLOR = sys.stdout.isatty()
def paint(code, text):
    return f"\033[{code}m{text}\033[0m" if COLOR else text
def dim(t):    return paint("2", t)
def bold(t):   return paint("1", t)
def green(t):  return paint("32", t)
def yellow(t): return paint("33", t)
def red(t):    return paint("31", t)
def cyan(t):   return paint("36", t)

# --------------------------------------------------------------------------
# discovery & sampling

def qs_pids():
    """Pids of the running shell server(s): `qs -p <path>` with no ipc args."""
    out = subprocess.run(["pgrep", "-af", r"qs -p .*silhouette-shell"],
                         capture_output=True, text=True).stdout
    pids = []
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and "ipc" not in parts[1]:
            pids.append(int(parts[0]))
    return sorted(pids)

def shell_pid():
    pids = qs_pids()
    return pids[0] if pids else None

def mem_kb(pid):
    """(rss, anon, swap) in KiB for a pid, or (0,0,0)."""
    try:
        with open(f"/proc/{pid}/status") as f:
            st = f.read()
        def kb(key):
            m = re.search(rf"^{key}:\s*(\d+)", st, re.M)
            return int(m.group(1)) if m else 0
        return kb("VmRSS"), kb("RssAnon"), kb("VmSwap")
    except (FileNotFoundError, ProcessLookupError):
        return 0, 0, 0

def sample(pid, tag):
    rss, anon, swap = mem_kb(pid)
    return {"t": time.monotonic(), "tag": tag, "rss_kb": rss,
            "anon_kb": anon, "swap_kb": swap}

def fmt_mb(kb):
    return f"{kb / 1024:8.1f} MB"

# --------------------------------------------------------------------------
# session / lock state

def wayland_session_id():
    out = subprocess.run(["loginctl", "list-sessions", "--no-legend"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 6 and parts[5] == "wayland":
            return parts[0]
    return None

def locked():
    """Best-effort lock detection: logind LockedHint + a 'lock' layer/namespace."""
    sid = wayland_session_id()
    if sid:
        out = subprocess.run(["loginctl", "show-session", sid, "-p", "LockedHint"],
                             capture_output=True, text=True).stdout
        if "LockedHint=yes" in out:
            return True
    out = subprocess.run(["hyprctl", "layers"], capture_output=True, text=True).stdout
    if re.search(r"namespace:.*lock", out, re.I):
        return True
    return False

def wait_unlocked(timeout, poll=1.0):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        if not locked():
            return True
        time.sleep(poll)
    return not locked()

# --------------------------------------------------------------------------
# shell control

def ipc(*args, timeout=15):
    cmd = IPC + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr).strip()

def relaunch():
    """Start the shell detached, mirroring hypr/scripts/reload.sh."""
    log = os.path.join(LOG_DIR, "qs.log")
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "ab") as lf:
        subprocess.Popen(["qs", "-p", SHELL_PATH], stdout=lf, stderr=lf,
                         stdin=subprocess.DEVNULL, start_new_session=True)
    print(f"  relaunched: qs -p {SHELL_PATH}  (log: {dim(log)})")

def wait_shell_up(timeout=20, poll=0.3):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        pid = shell_pid()
        if pid:
            rss, _, _ = mem_kb(pid)
            if rss > 0:
                return pid
        time.sleep(poll)
    return None

def restart_shell(quiet=False):
    """Kill the current shell and relaunch it. Refuses while locked."""
    pid = shell_pid()
    if pid is None:
        if quiet:
            print(f"  {yellow('no running shell — starting one')}")
            relaunch()
            return wait_shell_up(), True
        print(f"  {red('no running shell found')} (qs -p ... silhouette-shell)")
        return None, False
    print(f"  pid {cyan(str(pid))}  rss {fmt_mb(mem_kb(pid)[0])}")
    if locked():
        print(red("  session is LOCKED — refusing to restart (use --wait-unlock, "
                  "or unlock first)"))
        return None, False
    os.kill(pid, signal.SIGTERM)
    t0 = time.monotonic()
    while time.monotonic() - t0 < 8 and pid in qs_pids():
        time.sleep(0.2)
    if pid in qs_pids():
        print(f"  {yellow('still alive after TERM — SIGKILL')}")
        os.kill(pid, signal.SIGKILL)
        time.sleep(0.5)
    relaunch()
    new = wait_shell_up()
    if new is None:
        print(red("  shell did not come back up!"))
    else:
        rss, anon, _ = mem_kb(new)
        print(f"  up as pid {cyan(str(new))}  rss {fmt_mb(rss)}  anon {fmt_mb(anon)}")
    return new, new is not None

def ensure_shell(quiet=True):
    """Guarantee a shell is running; returns pid (or None if impossible)."""
    pid = shell_pid()
    if pid:
        return pid
    relaunch()
    return wait_shell_up()

# --------------------------------------------------------------------------
# phases

def measure(pid, secs, tag, every=0.5):
    """Sample RSS over `secs` seconds; return peak & samples."""
    peak = 0
    rows = []
    t0 = time.monotonic()
    while time.monotonic() - t0 < secs:
        rss, anon, swap = mem_kb(pid)
        if rss > peak:
            peak = rss
        rows.append({"t": time.monotonic(), "tag": tag, "rss_kb": rss,
                     "anon_kb": anon, "swap_kb": swap})
        time.sleep(every)
    return peak, rows

def run_soak(args):
    out = []
    def log(s=""):
        print(s)
        out.append(s)

    ts = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    log_path = os.path.join(LOG_DIR, f"soak-{ts}.log")
    os.makedirs(LOG_DIR, exist_ok=True)

    # -- phase 0: preflight -----------------------------------------------
    if args.wait_unlock and locked():
        log(yellow("  lock active — waiting for unlock (--wait-unlock)"))
        if not wait_unlocked(300):
            log(red("  still locked after 300s; aborting"))
            return 3
    elif locked():
        log(red("  session is LOCKED — aborting. Unlock, or pass --wait-unlock."))
        return 3
    if shell_pid() is None and not args.restart:
        log(yellow("  no shell running — will launch one"))

    # -- phase 1: restart (optional) --------------------------------------
    if args.restart:
        log(bold("\n== restart =="))
        pid, ok = restart_shell()
        if not ok:
            return 2
        time.sleep(4)   # let surfaces/OSD settle before baseline
        log("")
    else:
        pid = ensure_shell()
        if pid is None:
            log(red("  cannot start shell"))
            return 2
    baseline = mem_kb(pid)[0]
    log(bold("== baseline =="))
    log(f"  rss {fmt_mb(baseline)}   anon {fmt_mb(mem_kb(pid)[1])}   pid {cyan(str(pid))}")

    # -- phase 2: surface stress ------------------------------------------
    surfaces = [s for s in args.surfaces if s not in RISKY]
    skipped = [s for s in args.surfaces if s in RISKY]
    if skipped:
        log(dim(f"  (skipping risky surfaces: {' '.join(skipped)})"))

    log(bold("\n== stress =="))
    log(dim("  surface".ljust(14) + "open".rjust(14) + "peak".rjust(14)
            + "closed".rjust(14)))
    rows = []
    ipc("pill", "hide")  # deterministic start: nothing open
    for cycle in range(1, args.cycles + 1):
        for s in surfaces:
            if cycle > 1:
                log("")
            rc, err = ipc("pill", s, "")
            if rc != 0:
                log(f"  {s.ljust(14)}{yellow('ipc failed: ' + (err or '?'))}")
                continue
            time.sleep(args.open)                     # async build + morph settle
            open_kb = mem_kb(pid)[0]
            _, peek_rows = measure(pid, args.peak, f"open:{s}", every=0.4)
            peak_kb = max(r["rss_kb"] for r in peek_rows)
            rc, _ = ipc("pill", "hide")
            time.sleep(args.hold)                     # close dissolve + reclaimer
            closed_kb = mem_kb(pid)[0]
            log(f"  {s.ljust(14)}{fmt_mb(open_kb)}{fmt_mb(peak_kb)}"
                f"{fmt_mb(closed_kb)}")
            rows.append({"surface": s, "cycle": cycle, "open_kb": open_kb,
                         "peak_kb": peak_kb, "closed_kb": closed_kb})

    # -- phase 3: reclaim check -------------------------------------------
    log(bold("\n== reclaim =="))
    log(dim(f"  holding {args.reclaim}s idle so the 12s reclaimer + 10s cleaner "
            "tick can destroy closed surfaces"))
    before = mem_kb(pid)[0]
    _, rc_rows = measure(pid, args.reclaim, "reclaim", every=1.0)
    after = mem_kb(pid)[0]
    log(f"  before {fmt_mb(before)}   after {fmt_mb(after)}   "
        f"returned {(after - before) / 1024:+.1f} MB")

    # -- phase 4: quiet trend ----------------------------------------------
    log(bold(f"\n== quiet ({args.quiet}s) =="))
    _, q_rows = measure(pid, args.quiet, "quiet", every=1.0)
    q_b = q_rows[0]["rss_kb"]
    q_e = q_rows[-1]["rss_kb"]
    n = len(q_rows)
    sx = sum(r["t"] - q_rows[0]["t"] for r in q_rows)
    sy = sum(r["rss_kb"] for r in q_rows)
    sxy = sum((r["t"] - q_rows[0]["t"]) * r["rss_kb"] for r in q_rows)
    sxx = sum((r["t"] - q_rows[0]["t"]) ** 2 for r in q_rows)
    slope = (n * sxy - sx * sy) / (n * sxx - sx * sx) if n * sxx != sx * sx else 0.0
    log(f"  start {fmt_mb(q_b)}   end {fmt_mb(q_e)}   "
        f"trend {slope * 60 / 1024:+.2f} MB/min")

    # -- summary ------------------------------------------------------------
    peak_all = max((r["peak_kb"] for r in rows), default=0)
    end_kb = mem_kb(pid)[0]
    log(bold("\n==== summary ===="))
    log(f"  baseline : {fmt_mb(baseline)}")
    log(f"  peak     : {fmt_mb(max(peak_all, end_kb))}")
    log(f"  end      : {fmt_mb(end_kb)}")
    log(f"  net      : {(end_kb - baseline) / 1024:+.1f} MB over the run")
    log(f"  trend    : {slope * 60 / 1024:+.2f} MB/min idle (quiet phase)")
    log(dim(f"  log: {log_path}"))
    log(dim("  tip: a net that keeps growing per cycle = a leak in the "
            "open/close path; an idle trend above ~+1 MB/min = a slow leak"))

    # persist a machine-readable log next to the human one
    payload = {"ts": ts, "baseline_kb": baseline, "end_kb": end_kb,
               "peak_kb": max(peak_all, end_kb), "trend_mb_min": slope * 60 / 1024,
               "rows": rows}
    with open(log_path + ".json", "w") as f:
        json.dump(payload, f, indent=2)
    with open(log_path, "w") as f:
        f.write("\n".join(out) + "\n")
    return 0

def main():
    ap = argparse.ArgumentParser(description="memory soak for silhouette-shell")
    ap.add_argument("--no-restart", dest="restart", action="store_false",
                    help="don't restart the shell first")
    ap.add_argument("--restart", dest="restart", action="store_true",
                    help="restart the shell first (default)")
    ap.set_defaults(restart=True)
    ap.add_argument("--cycles", type=int, default=1, help="stress cycles (default 1)")
    ap.add_argument("--open", type=float, default=2.5,
                    help="seconds to wait after opening a surface (default 2.5)")
    ap.add_argument("--peak", type=float, default=1.5,
                    help="seconds to sample the open peak (default 1.5)")
    ap.add_argument("--hold", type=float, default=4.0,
                    help="seconds to wait after closing (default 4)")
    ap.add_argument("--reclaim", type=float, default=26.0,
                    help="idle seconds to wait for the reclaimer (default 26)")
    ap.add_argument("--quiet", type=float, default=20.0,
                    help="quiet soak length, seconds (default 20)")
    ap.add_argument("--surfaces", default=" ".join(DEFAULT_SURFACES),
                    help="space-separated surface names to cycle")
    ap.add_argument("--wait-unlock", action="store_true",
                    help="wait (up to 300s) for the session to unlock instead of aborting")
    ap.add_argument("--color", choices=["auto", "always", "never"], default="auto")
    args = ap.parse_args()
    global COLOR
    if args.color == "always":
        COLOR = True
    elif args.color == "never":
        COLOR = False

    if not shutil.which("qs"):
        print(red("qs not found on PATH"), file=sys.stderr)
        return 1
    if "WAYLAND_DISPLAY" not in os.environ or "HYPRLAND_INSTANCE_SIGNATURE" not in os.environ:
        print(red("no Wayland/Hyprland env — refusing to run outside a session"),
              file=sys.stderr)
        return 1
    args.surfaces = args.surfaces.split()
    return run_soak(args)

if __name__ == "__main__":
    code = 0
    try:
        code = main()
    except KeyboardInterrupt:
        print("\ninterrupted")
        code = 130
    finally:
        # Never leave the user without a shell.
        if ensure_shell() is None:
            print(red("could not restart the shell — check qs.log"), file=sys.stderr)
            code = code or 2
        else:
            print(dim("shell running (pid %s)" % shell_pid()))
    sys.exit(code)
