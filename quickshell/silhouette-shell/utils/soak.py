#!/usr/bin/env python3
"""
soak.py — memory soak for the silhouette-shell quickshell config.

The shell is one process now: shell.qml composes the pill, the lock, the screen
corners, the standalone launcher, the reload popup and the settings dialog, and
every surface, window and the memory saver that frees them live inside it. So
"the shell" is a single qs server, and this measures that one process:

  restart   optionally restart it first (SIGTERM + relaunch, the same shape
            hypr/scripts/reload.sh has) — never while the session is locked
  stress    open + close every pill surface once through the pill's generic
            `page` door, sampling RSS at each step
  dialog    toggle the settings dialog, whose window is built on first open and
            torn down again five seconds after it closes, so its memory comes
            back lazily rather than at the close
  reclaim   whether each closed surface actually gave its memory back: every
            close is followed by `pill unloadAll` while that surface is the only
            one closed, so what the drop returns is that surface's own tree, and
            one further surface is left to the memory saver's own tier tail to
            prove the timed sweep fires without the manual door
  quiet     idle soak with a least-squares trend (MB/min) to catch slow leaks

It is deliberately safe around the lock: it refuses to restart while the lock is
up (or waits with --wait-unlock), and always relaunches the shell at exit if it
finds none running. The lock is in-process too, so logind's LockedHint is the
only signal an outside tool has for it — pass --allow-locked to override if the
session is locked and you know it is not.

Usage:
  soak.py [--no-restart] [--cycles N] [--surfaces "a b c"] [--no-dialog]
          [--open SEC] [--peak SEC] [--hold SEC] [--no-warmup] [--no-per-surface]
          [--leak-tol MB] [--reclaim SEC] [--timed-surface NAME]
          [--dialog-teardown SEC] [--quiet SEC] [--wait-unlock] [--allow-locked]
          [--color auto|always|never]

Env knobs:
  QS_IPC        full ipc client command (default: the form the running shell was
                started with, else `qs -c silhouette-shell ipc call`)
  SHELL_PATH    config dir (default: ~/.config/quickshell/silhouette-shell/)
  XDG_STATE_HOME  state root the logs land under (…/silhouette)

Requires python3, a running Hyprland session, and the shell running as
`qs -p <path>` or `qs -c silhouette-shell`. Read-only otherwise.
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
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")), "silhouette")
LOG_DIR = STATE_DIR
FLAGS_PATH = os.path.join(STATE_DIR, "flags.json")

# The memory saver's short tier (Pill.qml unloadIdleMs): the two heaviest surfaces
# are swept at the base tail, everything else after one double-length reset.
BASE_TIER = {"wallpaper", "mixer"}

# RSS that may stay behind after a surface's own tree is dropped, in KiB, before a
# probe calls it kept memory: background services (network scans, bluetooth, the
# calendar's own sync) move RSS by hundreds of KiB on their own, so a surface that
# returns to within this band of where it started counts as returned.
LEAK_TOL_KB = 1024

# Unmeasured warm-up open/close per surface on the first cycle: enough for the
# deferred QML compile (the loader caches the compiled type for the session) and
# the service the surface reads to wake, without paying the measuring delays.
WARM_OPEN = 1.2
WARM_HOLD = 1.5

# Surfaces whose open has real side effects or needs external state — excluded
# from the default cycle. The recorder wants gpu-screen-recorder (or the ffmpeg
# portal fallback) and starts capturing; updates wants the network and an
# AppImage registry; polkit wants a live prompt parked on the service and is
# non-dismissible while one is. (`quickRecord` is not a surface at all — it is a
# recorder alias on the pill's IPC handler — so it cannot be listed here.)
# `media` silently no-ops with no player loaded (`if (Players.has)`), and `timer`
# refuses to be evicted while a timer runs; both stay in for the peak-memory
# read, and the table prints a note when they look like no-ops.
RISKY = {"recorder", "updates", "polkit"}
DEFAULT_SURFACES = (
    "calendar launcher clipboard wallpaper settings keybinds workspaces stash "
    "spaceapps appearance display input look idlelock animation fontpicker "
    "sysmon battery power mixer link weather timer media"
).split()

COLOR = sys.stdout.isatty()
# Set from --allow-locked: the lock is in-process now, so logind's LockedHint is
# the only signal this script has for it and it can be wrong.
ALLOW_LOCKED = False
# True once a run is under way, so the exit handler only relaunches a shell it
# actually took (not on --help, which never touches anything).
RUNNING = False

# Seconds a killed shell is given to be brought back by the session's supervisor
# (the watchdog in hypr/modules/autostart.lua, which notices on its own 5s tick)
# before this script launches one by hand. Launching as well is the race that
# leaves two shells up.
SUPERVISOR_GRACE = 12.0

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
#
# Both spellings name the same config — the directory under
# ~/.config/quickshell is silhouette-shell, so `-c silhouette-shell` and
# `-p ~/.config/quickshell/silhouette-shell` hand quickshell the same tree — but
# a session may use either (`launch.sh` starts one form, the desktop entry and
# every keybind call the other), so both have to count as "the shell". A scan of
# /proc catches both plus the `quickshell` binary name, where a pgrep pattern
# only ever matched the one it was written for.

def _argv_of(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
    except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
        return []

def _is_shell_invocation(argv):
    """True for a shell *server*, false for an `ipc call` client of one."""
    if not argv or os.path.basename(argv[0]) not in ("qs", "quickshell"):
        return False
    if "ipc" in argv[1:]:
        return False
    for i, a in enumerate(argv):
        if a == "-p" and i + 1 < len(argv) and "silhouette-shell" in argv[i + 1]:
            return True
        if a == "-c" and i + 1 < len(argv) and argv[i + 1] == "silhouette-shell":
            return True
    return False

def shell_instances():
    """[(pid, argv)] for every running shell server, oldest first."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        argv = _argv_of(int(entry))
        if _is_shell_invocation(argv):
            found.append((int(entry), argv))
    return sorted(found)

def shell_pids():
    return [pid for pid, _ in shell_instances()]

def shell_pid():
    pids = shell_pids()
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

def fmt_mb(kb):
    return f"{kb / 1024:8.1f} MB"

def delta_mb(a_kb, b_kb):
    """b − a in MB, signed and padded: negative means memory came back."""
    return f"{(b_kb - a_kb) / 1024:+7.1f} MB"

# --------------------------------------------------------------------------
# session / lock state

def session_id():
    """The session this script runs in. XDG_SESSION_ID is set by any session
    login; the fallback takes loginctl's first session, which is the login's on a
    single-seat machine.
    """
    sid = os.environ.get("XDG_SESSION_ID")
    if sid:
        return sid
    out = subprocess.run(["loginctl", "list-sessions", "--no-legend"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            return parts[0]
    return None

def locked():
    """Best-effort lock detection: logind's LockedHint, plus a 'lock' layer.

    The shell hosts the lock itself now (modules/lock, a WlSessionLock), so
    there is no locker process to look for and no compositor query for session
    lock state; logind is the one outside signal, and it is only set when
    whoever locked the session asked logind to (hypridle's before_sleep does).
    The layer probe stays for any other locker that registers one.
    """
    sid = session_id()
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

def ipc_cmd():
    """The client command that reaches the running instance.

    `qs ipc call` reaches a running instance only, and the instance is keyed by
    how it was started, so mirror the form the running shell used; fall back to
    the name form every keybind and the desktop entry use.
    """
    if os.environ.get("QS_IPC"):
        return os.environ["QS_IPC"].split()
    inst = shell_instances()
    if inst:
        argv = inst[0][1]
        for i, a in enumerate(argv):
            if a in ("-p", "-c") and i + 1 < len(argv):
                return [argv[0], a, argv[i + 1]]
    return ["qs", "-c", "silhouette-shell"]

def ipc(*args, timeout=20):
    r = subprocess.run(ipc_cmd() + ["ipc", "call"] + list(args),
                       capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr).strip()

def launch_form():
    """(flag, value) to start the shell with — the running instance's own form."""
    inst = shell_instances()
    if inst:
        argv = inst[0][1]
        for i, a in enumerate(argv):
            if a in ("-p", "-c") and i + 1 < len(argv):
                return a, argv[i + 1]
    return "-p", SHELL_PATH

def relaunch():
    """Start the shell detached, mirroring hypr/scripts/reload.sh (qs.log)."""
    flag, val = launch_form()
    log = os.path.join(LOG_DIR, "qs.log")
    os.makedirs(LOG_DIR, exist_ok=True)
    binary = shutil.which("qs") or "qs"
    with open(log, "ab") as lf:
        subprocess.Popen([binary, flag, val], stdout=lf, stderr=lf,
                         stdin=subprocess.DEVNULL, start_new_session=True)
    print(f"  relaunched: qs {flag} {val}  (log: {dim(log)})")

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

def restart_shell():
    """Kill every running shell server and relaunch one. Refuses while locked."""
    inst = shell_instances()
    pids = [p for p, _ in inst]
    if not pids:
        print(f"  {red('no running shell found')} (qs -p <dir> / qs -c silhouette-shell)")
        return None, False
    for pid in pids:
        print(f"  pid {cyan(str(pid))}  rss {fmt_mb(mem_kb(pid)[0])}")
    if not ALLOW_LOCKED and locked():
        print(red("  session is LOCKED — refusing to restart (use --wait-unlock, "
                  "or unlock first)"))
        return None, False
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    t0 = time.monotonic()
    while time.monotonic() - t0 < 8 and any(p in shell_pids() for p in pids):
        time.sleep(0.2)
    for pid in pids:
        if pid in shell_pids():
            print(f"  {yellow('pid %d still alive after TERM — SIGKILL' % pid)}")
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            time.sleep(0.5)
    # Killing the shell is the whole restart when the watchdog is up: it sees IPC
    # stop answering and brings one back through launch.sh. Hand that window over
    # before launching directly — doing both at once is what leaves two shells
    # fighting over the layer surface, and the direct launch is only for a session
    # with no supervisor running at all.
    print(dim(f"  waiting up to {SUPERVISOR_GRACE:g}s for the supervisor to respawn it"))
    new = wait_shell_up(timeout=SUPERVISOR_GRACE)
    if new is None:
        print(dim("  nothing respawned it — launching directly"))
        relaunch()
        new = wait_shell_up()
    if new is None:
        print(red("  shell did not come back up!"))
    else:
        rss, anon, _ = mem_kb(new)
        print(f"  up as pid {cyan(str(new))}  rss {fmt_mb(rss)}  anon {fmt_mb(anon)}")
    return new, new is not None

def ensure_shell():
    """Guarantee a shell is running; returns pid (or None if impossible)."""
    pid = shell_pid()
    if pid:
        return pid
    relaunch()
    return wait_shell_up()

# --------------------------------------------------------------------------
# memory saver (Pill.qml's tier table, as configured in flags.json)

def _num(v, default):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default

def saver_config():
    """{on, base, sweep} from the shell's flags, defaulting to Flags.qml."""
    cfg = {"on": True, "base": 12, "sweep": 10}
    try:
        with open(FLAGS_PATH) as f:
            flags = json.load(f)
        cfg["on"] = bool(flags.get("memorySaver", True))
        cfg["base"] = _num(flags.get("pillSurfaceIdleTimeout"), cfg["base"])
        cfg["sweep"] = _num(flags.get("pillCleanupSec"), cfg["sweep"])
    except (OSError, ValueError):
        pass
    return cfg

def base_tail(cfg):
    """The base tail in seconds — Pill.qml floors pillSurfaceIdleTimeout at 10."""
    return max(10, cfg["base"])

def tier_tail(name, cfg):
    """Tail (seconds) before a closed `name` is swept, from Pill.qml's table: the
    two heaviest surfaces go at exactly the base, everything else gets double."""
    return base_tail(cfg) if name in BASE_TIER else 2 * base_tail(cfg)

def timed_wait(name, cfg):
    """Tier tail for `name` plus one sweep tick — when its own tier has certainly run."""
    return tier_tail(name, cfg) + max(1, cfg["sweep"])

def saver_line(cfg):
    if not cfg["on"]:
        return dim("  memory saver OFF — the timed sweep never fires; closed "
                   "surfaces stay resident until `pill unloadAll` or a restart")
    return dim(f"  memory saver on: base {base_tail(cfg)}s (floored at 10), "
               f"heaviest tier {base_tail(cfg)}s / rest {2 * base_tail(cfg)}s, "
               f"sweep every {max(1, cfg['sweep'])}s")

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
    if not rows:  # secs was 0 — still take one reading
        rss, anon, swap = mem_kb(pid)
        rows.append({"t": time.monotonic(), "tag": tag, "rss_kb": rss,
                     "anon_kb": anon, "swap_kb": swap})
        peak = rss
    return peak, rows

def slope_mb_min(rows):
    """Least-squares RSS trend over a sample run, in MB/min."""
    n = len(rows)
    if n < 3:
        return 0.0
    t0 = rows[0]["t"]
    sx = sum(r["t"] - t0 for r in rows)
    sy = sum(r["rss_kb"] for r in rows)
    sxy = sum((r["t"] - t0) * r["rss_kb"] for r in rows)
    sxx = sum((r["t"] - t0) ** 2 for r in rows)
    denom = n * sxx - sx * sx
    if denom == 0:
        return 0.0
    return ((n * sxy - sx * sy) / denom) * 60 / 1024

def run_soak(args):
    global RUNNING
    RUNNING = True
    out = []
    def log(s=""):
        print(s)
        out.append(s)

    ts = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    log_path = os.path.join(LOG_DIR, f"soak-{ts}.log")
    os.makedirs(LOG_DIR, exist_ok=True)

    cfg = saver_config()

    # -- phase 0: preflight -----------------------------------------------
    if not ALLOW_LOCKED and locked():
        if args.wait_unlock:
            log(yellow("  lock active — waiting for unlock (--wait-unlock)"))
            if not wait_unlocked(300):
                log(red("  still locked after 300s; aborting"))
                return 3
        else:
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
        time.sleep(4)   # let the surfaces/OSD settle before the baseline
    else:
        pid = ensure_shell()
        if pid is None:
            log(red("  cannot start shell"))
            return 2
    baseline = mem_kb(pid)[0]
    log(bold("\n== baseline =="))
    log(f"  rss {fmt_mb(baseline)}   anon {fmt_mb(mem_kb(pid)[1])}   pid {cyan(str(pid))}")
    log(saver_line(cfg))
    log("")

    # -- phase 2: surface stress ------------------------------------------
    #
    # Every surface is opened through the generic `page` door: it is the one
    # function on the pill's IPC handler that covers the whole surface table,
    # including the ones with no named handler of their own (workspaces, stash,
    # spaceapps, appearance, display, input, look, idlelock, animation,
    # fontpicker, weather), so this list never has to be kept in lockstep with
    # the handler. An empty monitor argument resolves to the focused monitor
    # inside toggleSurface, so no hyprctl round trip here either.
    surfaces = [s for s in args.surfaces if s not in RISKY]
    skipped = [s for s in args.surfaces if s in RISKY]
    if skipped:
        log(dim(f"  (skipping risky surfaces: {' '.join(skipped)})"))

    log(bold("== stress =="))
    log(dim("  " + "surface".ljust(14) + "open".rjust(11) + "peak".rjust(11)
            + "closed".rjust(11) + "Δ".rjust(11)))
    rows = []
    ipc("pill", "hide")  # deterministic start: nothing open
    for cycle in range(1, args.cycles + 1):
        if cycle > 1:
            log("")
        if args.cycles > 1:
            log(dim(f"  cycle {cycle}/{args.cycles}"))
        for s in surfaces:
            if args.warmup and cycle == 1:
                # Unmeasured warm-up open. The first open compiles the surface's
                # component (the loader keeps that compiled type for the session)
                # and wakes whatever service it reads, and neither comes back on
                # a drop. Measuring the reclaim against a baseline from before
                # that would blame the surface for a cost every session pays once
                # — it showed up as 3 MB "kept" by the power surface, whose own
                # tree is a few hundred KiB.
                #
                # The warm-up's own tree is then dropped as well: the saver's
                # tail has not elapsed yet, so a warm-up that stopped at the
                # close would hand the measured cycle a build that costs nothing
                # (the tree is already resident) and a drop that frees the
                # warm-up's tree instead of the measured one.
                ipc("pill", "page", "", s)
                time.sleep(WARM_OPEN)
                ipc("pill", "hide")
                time.sleep(WARM_HOLD)
                ipc("pill", "unloadAll")
                time.sleep(args.unload_settle)
            before_kb = mem_kb(pid)[0]
            rc, err = ipc("pill", "page", "", s)
            if rc != 0:
                log(f"  {s.ljust(14)}{yellow('ipc failed: ' + (err or '?'))}")
                continue
            time.sleep(args.open)                     # async build + morph settle
            open_kb = mem_kb(pid)[0]
            _, peek_rows = measure(pid, args.peak, f"open:{s}", every=0.4)
            peak_kb = max(r["rss_kb"] for r in peek_rows)
            ipc("pill", "hide")
            time.sleep(args.hold)                     # close dissolve
            closed_kb = mem_kb(pid)[0]
            log(f"  {s.ljust(14)}{fmt_mb(open_kb)}{fmt_mb(peak_kb)}"
                f"{fmt_mb(closed_kb)}{delta_mb(open_kb, closed_kb)}")
            row = {"surface": s, "cycle": cycle, "before_kb": before_kb,
                   "open_kb": open_kb, "peak_kb": peak_kb, "closed_kb": closed_kb,
                   "dropped_kb": None}
            if args.per_surface:
                # The reclaim probe: at this instant this surface is the only one
                # closed and resident, so what the drop returns is its own tree.
                rc, err = ipc("pill", "unloadAll")
                if rc != 0:
                    log(f"  {yellow('pill unloadAll failed: ' + (err or '?'))}")
                time.sleep(args.unload_settle)
                row["dropped_kb"] = mem_kb(pid)[0]
            rows.append(row)

    # -- phase 3: settings dialog ------------------------------------------
    #
    # The dialog lives in this same process now, and its lifecycle is the
    # interesting part: the FloatingWindow is built on the first open and
    # destroyed five seconds after it closes, so the memory it costs does not
    # come back at the close. `hide` and `toggle` are the safe calls — `show` is
    # swallowed by `qs ipc` itself (the README's warning) and never reaches the
    # handler.
    dialog = None
    if args.dialog:
        log(bold("\n== dialog =="))
        log(dim("  " + "dialog".ljust(14) + "before".rjust(11) + "peak".rjust(11)
                + "after".rjust(11) + "Δ".rjust(11)))
        before = mem_kb(pid)[0]
        rc, err = ipc("settings", "toggle")
        if rc != 0:
            log(f"  {yellow('settings toggle failed: ' + (err or '?'))}")
        else:
            time.sleep(args.open)
            _, d_rows = measure(pid, args.peak, "dialog", every=0.4)
            peak_kb = max(r["rss_kb"] for r in d_rows)
            ipc("settings", "hide")
            log(dim(f"  holding {args.dialog_teardown:g}s: the window teardown "
                    "starts 5s after the close"))
            time.sleep(args.dialog_teardown)
            after = mem_kb(pid)[0]
            log(f"  {'settings'.ljust(14)}{fmt_mb(before)}{fmt_mb(peak_kb)}"
                f"{fmt_mb(after)}{delta_mb(peak_kb, after)}")
            dialog = {"before_kb": before, "peak_kb": peak_kb, "after_kb": after}

    # -- phase 4: reclaim ---------------------------------------------------
    #
    # Two doors, and both are reported per surface. The manual one (`pill
    # unloadAll`) was measured inside the stress loop, right after each close,
    # because at that instant the surface that just closed is the only one
    # closed and resident — so whatever the drop returns is its own component
    # tree, not an accumulation of everything the run touched. The timed one
    # sweeps on its own schedule and cannot be isolated per surface, so it gets
    # one surface to itself at the end, left alone for its own tier tail.
    log(bold("\n== reclaim =="))
    log(saver_line(cfg))

    probed = [r for r in rows if r["dropped_kb"] is not None]
    offenders = []
    timed = None
    if probed:
        log(dim("  per surface: `pill unloadAll` right after each close, while that "
                "surface is the only one closed — so the drop is its own tree. "
                "`held` is what it still had at close, `freed` what the drop returned"))
        log(dim("  " + "surface".ljust(14) + "closed".rjust(11) + "dropped".rjust(11)
                + "held".rjust(11) + "freed".rjust(11) + "   verdict"))
        for r in probed:
            held = r["closed_kb"] - r["before_kb"]
            freed = r["closed_kb"] - r["dropped_kb"]
            kept = r["dropped_kb"] - r["before_kb"]
            if held < LEAK_TOL_KB:
                why = ("no player loaded, so the handler no-oped" if r["surface"] == "media"
                       else ("nothing was running, or a running timer is pinned rather "
                             "than evicted" if r["surface"] == "timer"
                             else "its tree is under the tolerance"))
                verdict = dim(f"nothing held ({why})")
            elif freed >= held - LEAK_TOL_KB:
                verdict = green("returned")
            else:
                verdict = red(f"kept {kept / 1024:.1f} MB")
                offenders.append(r["surface"])
            log(f"  {r['surface'].ljust(14)}{fmt_mb(r['closed_kb'])}{fmt_mb(r['dropped_kb'])}"
                f"{delta_mb(r['before_kb'], r['closed_kb']).rjust(11)}"
                f"{delta_mb(r['dropped_kb'], r['closed_kb']).rjust(11)}   {verdict}")
        if offenders:
            log(red(f"  {len(offenders)}/{len(probed)} surfaces did not give their memory "
                    f"back: {' '.join(offenders)}"))
            log(dim(f"  the shell also moved {(mem_kb(pid)[0] - baseline) / 1024:+.1f} MB on "
                    "its own over the run (baseline -> now): a row within a MB or two of "
                    "the line is usually that drift, not the surface"))
        else:
            log(green(f"  all {len(probed)} surface" + ("s" if len(probed) != 1 else "")
                      + " returned to where they started"))
    else:
        log(dim("  per-surface probes skipped (--no-per-surface)"))

    # The timed door needs a surface of its own, and one on the short tier is the
    # cheapest way to watch it: its tail is the base, not the doubled one.
    if args.timed_surface not in ("", "auto"):
        name = args.timed_surface
        if name not in surfaces:
            log(dim(f"  note: --timed-surface {name} is not in this run's surface list"))
    else:
        name = next((s for s in surfaces if s in BASE_TIER), surfaces[0] if surfaces else "")
    secs = args.reclaim if args.reclaim is not None else (
        timed_wait(name, cfg) if (name and cfg["on"]) else 0)

    if not cfg["on"]:
        log(dim("  timed sweep skipped: the memory saver is off, so a closed surface "
                "stays resident until `pill unloadAll` or a restart"))
    elif not name:
        log(dim("  timed sweep skipped: no surface in this run to leave to it"))
    elif secs <= 0:
        log(dim("  timed sweep skipped (--reclaim 0)"))
    else:
        tier = ("the base" if name in BASE_TIER else "2× the base")
        log(dim(f"  timed sweep: open + close {name}, then {secs:.0f}s idle — its own "
                f"tier ({tier_tail(name, cfg):.0f}s = {tier} {base_tail(cfg)}s) + one "
                f"{max(1, cfg['sweep'])}s sweep tick, with no manual drop"))
        ipc("pill", "hide")
        time.sleep(0.5)
        pre = mem_kb(pid)[0]
        ipc("pill", "page", "", name)
        time.sleep(args.open)
        ipc("pill", "hide")
        time.sleep(args.hold + secs)
        after = mem_kb(pid)[0]
        kept = after - pre
        timed = {"surface": name, "held_s": secs, "before_kb": pre,
                 "after_kb": after, "kept_kb": kept}
        verdict = (red(f"kept {kept / 1024:.1f} MB") if kept > LEAK_TOL_KB
                   else green("returned"))
        log(dim("  " + "surface".ljust(14) + "before".rjust(11) + "after".rjust(11)
                + "kept".rjust(11) + "   verdict"))
        log(f"  {name.ljust(14)}{fmt_mb(pre)}{fmt_mb(after)}"
            f"{delta_mb(pre, after).rjust(11)}   {verdict}")

    # -- phase 5: quiet trend ----------------------------------------------
    log(bold(f"\n== quiet ({args.quiet:g}s) =="))
    _, q_rows = measure(pid, args.quiet, "quiet", every=1.0)
    slope = slope_mb_min(q_rows)
    log(f"  start {fmt_mb(q_rows[0]['rss_kb'])}   end {fmt_mb(q_rows[-1]['rss_kb'])}   "
        f"trend {slope:+.2f} MB/min")

    # -- summary ------------------------------------------------------------
    peak_all = max((r["peak_kb"] for r in rows), default=0)
    if dialog:
        peak_all = max(peak_all, dialog["peak_kb"])
    end_kb = mem_kb(pid)[0]
    log(bold("\n==== summary ===="))
    log(f"  baseline  : {fmt_mb(baseline)}")
    peak_kb = max(peak_all, end_kb, baseline)
    log(f"  peak      : {fmt_mb(peak_kb)}")
    log(f"  end       : {fmt_mb(end_kb)}")
    log(f"  net       : {(end_kb - baseline) / 1024:+.1f} MB over the run")
    if probed:
        log(f"  reclaim   : {len(probed) - len(offenders)}/{len(probed)} surfaces returned"
            + ("" if not offenders else f" — kept: {' '.join(offenders)}"))
    if timed is not None:
        log(f"  timed     : {timed['surface']} "
            + ("returned" if timed["kept_kb"] <= LEAK_TOL_KB
               else f"kept {timed['kept_kb'] / 1024:.1f} MB") + " on its own tier")
    if dialog:
        log(f"  dialog    : {(dialog['peak_kb'] - dialog['after_kb']) / 1024:+.1f} MB "
            "returned after its teardown")
    log(f"  trend     : {slope:+.2f} MB/min idle (quiet phase)")
    log(dim(f"  log: {log_path}"))
    log(dim("  tip: a surface marked kept after `pill unloadAll` is a leak in its "
            "own tree (or its service); a timed sweep that keeps memory means the "
            "sweep is not running (Timers page); a net that grows per cycle = the "
            "open/close path; an idle trend above ~+1 MB/min = a slow leak"))

    payload = {"ts": ts, "baseline_kb": baseline, "end_kb": end_kb,
               "peak_kb": peak_kb, "trend_mb_min": slope,
               "saver": cfg, "leak_tol_kb": LEAK_TOL_KB,
               "reclaim": {
                   "per_surface": [{"surface": r["surface"], "before_kb": r["before_kb"],
                                    "peak_kb": r["peak_kb"], "closed_kb": r["closed_kb"],
                                    "dropped_kb": r["dropped_kb"],
                                    "held_kb": r["closed_kb"] - r["before_kb"],
                                    "freed_kb": r["closed_kb"] - r["dropped_kb"],
                                    "kept_kb": r["dropped_kb"] - r["before_kb"]}
                                   for r in probed],
                   "kept": offenders,
                   "timed": timed},
               "dialog": dialog, "rows": rows}
    with open(log_path + ".json", "w") as f:
        json.dump(payload, f, indent=2)
    with open(log_path, "w") as f:
        f.write("\n".join(out) + "\n")
    return 0

def main():
    global COLOR, ALLOW_LOCKED, LEAK_TOL_KB
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
                    help="seconds to wait after closing a surface (default 4)")
    ap.add_argument("--reclaim", type=float, default=None,
                    help="idle seconds to wait for the timed sweep in the end-of-run "
                         "probe; default is auto — the probe surface's own tier tail "
                         "+ one pillCleanupSec tick — and 0 skips it")
    ap.add_argument("--unload-settle", type=float, default=2.0,
                    help="seconds after each per-surface `pill unloadAll` before reading "
                         "RSS, i.e. the Loader teardown (default 2)")
    ap.add_argument("--warmup", dest="warmup", action="store_true",
                    help="open + close each surface once, unmeasured, before the "
                         "measured one so one-time compile/service costs are not "
                         "charged to its reclaim (default)")
    ap.add_argument("--no-warmup", dest="warmup", action="store_false")
    ap.set_defaults(warmup=True)
    ap.add_argument("--per-surface", dest="per_surface", action="store_true",
                    help="probe every closed surface with `pill unloadAll` right after its "
                         "own close, so the reclaim table is per surface (default)")
    ap.add_argument("--no-per-surface", dest="per_surface", action="store_false")
    ap.set_defaults(per_surface=True)
    ap.add_argument("--leak-tol", type=float, default=LEAK_TOL_KB / 1024,
                    help="MB a surface may still hold after its drop and count as "
                         "returned (default 1)")
    ap.add_argument("--timed-surface", default="auto",
                    help="surface to leave to the memory saver's own tier tail "
                         "(default: the heaviest tier of the ones in this run — "
                         "wallpaper or mixer)")
    ap.add_argument("--dialog", dest="dialog", action="store_true",
                    help="toggle the settings dialog and wait out its teardown (default)")
    ap.add_argument("--no-dialog", dest="dialog", action="store_false")
    ap.set_defaults(dialog=True)
    ap.add_argument("--dialog-teardown", type=float, default=8.0,
                    help="seconds to wait after closing the settings dialog: its window "
                         "is destroyed 5s after the close (default 8)")
    ap.add_argument("--quiet", type=float, default=20.0,
                    help="quiet soak length, seconds (default 20)")
    ap.add_argument("--surfaces", default=" ".join(DEFAULT_SURFACES),
                    help="space-separated surface names to cycle")
    ap.add_argument("--wait-unlock", action="store_true",
                    help="wait (up to 300s) for the session to unlock instead of aborting")
    ap.add_argument("--allow-locked", action="store_true",
                    help="run even if logind reports the session locked")
    ap.add_argument("--color", choices=["auto", "always", "never"], default="auto")
    args = ap.parse_args()

    if args.color == "always":
        COLOR = True
    elif args.color == "never":
        COLOR = False
    ALLOW_LOCKED = args.allow_locked
    LEAK_TOL_KB = max(0, int(args.leak_tol * 1024))

    if not shutil.which("qs"):
        print(red("qs not found on PATH"), file=sys.stderr)
        return 1
    if "WAYLAND_DISPLAY" not in os.environ or "HYPRLAND_INSTANCE_SIGNATURE" not in os.environ:
        print(red("no Wayland/Hyprland env — refusing to run outside a session"),
              file=sys.stderr)
        return 1
    if not os.path.exists(os.path.join(SHELL_PATH, "shell.qml")):
        print(red(f"no shell.qml under {SHELL_PATH} — set SHELL_PATH"), file=sys.stderr)
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
        # Never leave the user without a shell — but only a run that started one.
        if RUNNING and ensure_shell() is None:
            print(red("could not restart the shell — check qs.log"), file=sys.stderr)
            code = code or 2
        elif RUNNING:
            print(dim("shell running (pid %s)" % shell_pid()))
    sys.exit(code)
