# Memory

The shell's resident-memory goal is to stay under 200 MB at rest. That is a
real target, not a hope: the deferred-surface refactor alone (commit
`c7b2fd6`) took the full shell from ~220 MB to ~185 MB and PillRoot from
~213 MB to ~175 MB by compiling surfaces only on first open and reclaiming
them after 12 s idle. But memory is not something you tune once — every new
surface, widget or image adds resident cost, so the budget needs a readout
and a routine. `utils/soak.py` is that routine.

## How memory is spent

A few structural facts that shape where the bytes go:

- **One process hosts everything.** `shell.qml` composes PillRoot, LockRoot,
  LauncherRoot and ScreenCornerRoot in a single QML runtime, and the lock
  mounts in-process via `WlSessionLock`. That keeps the Qt/QML baseline to
  one copy and means locking is not a second ~100 MB process.
- **Everything scales with monitors.** Per monitor there is a reserve +
  overlay window, a full pill (hover face, tray row, OSD, Ame, ~28 surface
  loaders), and — while locked — a full-screen surface whose backdrop is a
  desktop grab decoded twice plus a ~10-pass blur chain.
- **Surfaces are lazy, and reclaimed.** `PillSurfaceLoader` compiles each
  surface on first open (the single largest chunk of the pill's startup
  memory stays unallocated until then) and `Pill.qml`'s idle cleaner
  destroys surfaces after 12 s closed. Images are mostly `sourceSize`-capped
  and the big grabs use `cache: false`.
- **Lock keeps sharp layers alive.** The lock's `deskOverlay` (a full-res
  sharp grab feeding a masked `MultiEffect`) stays resident for the whole
  lock session even when the mask hides 100% of it.

## Measuring: soak.py

`utils/soak.py` restarts the shell (exactly like `hypr/scripts/reload.sh`,
but **refusing while the session is locked**) and walks it through phases —
baseline, opening/closing every pill surface, an idle reclaim wait, and an
idle trend — printing a summary and writing
`~/.local/state/ricelin/soak-<timestamp>.log` (+ `.json` with the raw
samples). It samples `VmRSS` / `RssAnon` from `/proc/<pid>/status`.

```bash
python3 utils/soak.py                     # full run: restart + stress + reclaim + quiet
python3 utils/soak.py --no-restart        # run against the current instance as-is
python3 utils/soak.py --cycles 2 --surfaces "keybinds wallpaper link"   # leak probe
python3 utils/soak.py --wait-unlock       # wait (300s) for unlock instead of aborting
```

It only runs inside a live Hyprland session (refuses without
`WAYLAND_DISPLAY` / `HYPRLAND_INSTANCE_SIGNATURE`), skips surfaces with real
side effects (`recorder`, `updates`, `polkit`, `call`, `quickRecord`), never
kills anything while locked, and guarantees a shell is running on every exit
path — it cannot leave you stranded on a tty. Env knobs: `QS_IPC` (ipc
template) and `SHELL_PATH` (project path). Flags: `--cycles`, `--open`,
`--peak`, `--hold`, `--reclaim`, `--quiet`, `--surfaces`, `--color`.

## Measured numbers

Taken September 2026, single monitor, soak run:

- **Boot baseline** (fresh restart): ~170 MB RSS.
- **After opening all 24 surfaces once**: ~243 MB; overall peak 259.5 MB
  while keybinds was open.
- **Reclaim wait** (26 s idle past the 12 s reclaimer): ~243 MB — only
  ~2–7 MB came back.
- **Second cycle** on the same process (heavy surfaces only): plateaued at
  ~252 MB with no climb.
- **Idle trend**: flat, roughly ±0.2–0.4 MB/min.
- **High-water mark**: ~+73 MB above boot that never returns.

Quick readouts without the full soak:

```bash
pgrep -f quickshell | xargs ps -o pid,rss,vsz,cmd -p
```

## What the numbers mean

**There is no leak.** Repeated open/close cycles plateau instead of climbing
and idle is flat. What the soak caught is a **one-time high-water mark** of
~+73 MB: the first time every surface is touched the process allocates JS
heaps, shader/image caches and font atlases that it then keeps and reuses.
Freed surfaces' memory does not return to the OS (only a few MB come back
during reclaim, even though the 12 s reclaimer runs) — classic allocator
high-water behavior, not a leak.

Consequences: **under 200 MB is real at boot and in steady normal use, but
not after a session where everything has been opened once** — a long-lived
shell sits at ~240–250 MB "at rest" while a freshly booted one is ~170. The
release valves are a restart, or cutting what the first touch allocates.
The most expensive first-touchers are the big async surfaces: keybinds,
wallpaper, link, timer and weather.

Caveats: RSS undercounts real pressure when textures live on an iGPU —
watch `free -h` / cgroup pressure too, not just `ps`. And the 12 s idle
reclaim only returns RAM after a surface is *closed*, so a session that
opens everything once still peaks before reclaim can kick in. All numbers
scale with monitor count and grow while locked.

## Keeping it under 200 — levers, ranked by (impact × ease) / risk

1. **Make measuring a habit.** Add a `qs ipc call pill memory` handler
   (prints `/proc/self/status` `VmRSS`) and log RSS on surface
   open/close/lock/unlock. Establish the four numbers per release: boot
   RSS, peak after opening every surface once, locked peak, and a soak
   after unlock. Tuning without a readout decays.
2. **Free the lock's dead full-res overlay after the wipe.** Once the lock
   reveal's mask reaches full coverage, `deskOverlay` (full-res sharp grab +
   masked `MultiEffect`) is 100% invisible but stays resident all session.
   Dropping its `source` at that point frees a full-resolution texture per
   monitor — invisible change (`modules/lock/LockSurface.qml`).
3. **Don't decode lock grabs at full res.** `BlurredShot`'s `bgImg` and the
   sharp overlay both decode a monitor-res PNG before downsampling; the blur
   target is ⅛ resolution and the sharp layer only ever shows mid-wipe.
   Capping `sourceSize` at ~¼–½ screen turns a ~33 MB 4K decode into
   ~2–8 MB, per monitor.
4. **Look at the lock transient only if the lock dominates** a measurement:
   the sharp overlay + masked `MultiEffect` + white full-screen mask could
   collapse into one `ShaderEffect`. Visual risk for marginal gain — do not
   touch on spec.
5. **Primary-monitor-only tray row** on multi-monitor setups is a clean
   candidate (UX call — flag it before doing it).
6. **Cut the big first-touchers.** The expensive surfaces (keybinds,
   wallpaper, link, timer/weather) could go virtualized/lazier: fewer
   layers, smaller images, deferred lists, so their allocation spreads out
   instead of spiking at first open.

Whenever a feature lands, the question to answer is: *what did this add at
rest?* Run the soak before and after, and update the numbers above.
