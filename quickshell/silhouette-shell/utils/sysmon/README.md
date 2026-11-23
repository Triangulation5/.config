# Sysmon Sampler

Long-lived system metrics sampler for `services/Sysmon.qml`. Batches `/proc`, `/sys`, and `statvfs` reads into a single persistent process, replacing periodic fork-exec shell pipelines and reducing process churn to zero.

## Architecture & Fallback Ladder

[`run.sh`](run.sh) automatically executes the most optimized implementation available on the system:

1. **Tier 1 (Optimized Native Binary)**:
   * Architecture-specific binary at `bin/sysmon_sampler-<arch>` (e.g. `bin/sysmon_sampler-x86_64`) or root binary `sysmon_sampler`.
   * Written in pure standard library Rust ([`main.rs`](main.rs)), compiled with release optimizations (LTO, strip).
   * Negligible CPU usage, microsecond sampling latency, and sub-megabyte memory footprint.
2. **Tier 2 (Python 3 Fallback)**:
   * [`sampler.py`](sampler.py): Implements the exact same line protocol using Python's standard library.
   * Used if no compiled binary exists or if the binary cannot execute on the current system.
3. **Tier 3 (Universal POSIX Shell Fallback)**:
   * [`sampler.sh`](sampler.sh): Pure POSIX shell script.
   * Ensures that even on minimal environments without Rust or Python, the Sysmon surface functions without failure.

## Building Binary from Source

To compile the native binary on a new machine:
```bash
./utils/sysmon/build.sh
```
This will compile using `cargo` (or `rustc` if cargo is unavailable) and place the optimized binary into `bin/sysmon_sampler-$(uname -m)` and `sysmon_sampler`.

## Protocol & Cadence

Updates are emitted line-delimited over `stdout`:
* `DETECT TEMP <path>` / `DETECT GPU <vendor> [<dev> <has_vram>]`: Hardware probe (also supported standalone via `--detect-only`).
* `--once`: Samples CPU and memory vitals a single time and exits immediately.
* `--vitals-only [--interval <ms>]`: Persistent lightweight loop emitting only `CPU` and `MEM` at the requested interval (default 2000ms), skipping hardware/GPU/disk/net probes. Used by `services/BarStatus.qml` to eliminate periodic process forks.
* `--watch-pid <pid> [--interval <ms>]`: Persistent loop emitting `RSS <mb>` from `/proc/<pid>/statm` (default 8000ms), exiting cleanly if the target process exits. Used by `services/Surfaces.qml` to eliminate periodic `sh`/`getconf` forks.
* `CPU <total_jiffies> <idle_jiffies>`: Sampled every 1s.
* `MEM <mt> <ma> <st> <sf>`: Sampled every 1s (kB).
* `NET <rx> <tx>`: Sampled every 1s (bytes).
* `TMP <millidegrees>`: Sampled every 1s (or `TMP -`).
* `GPU_NV <csv>` / `GPU_AMD <busy> <temp> <vu> <vt>`: Sampled every 2s when a GPU is present. On NVIDIA, the Rust binary loads `libnvidia-ml.so.1` (NVML) directly via `dlopen` to avoid `nvidia-smi` forks, falling back to `nvidia-smi` if NVML is unavailable.
* `DISK <pct>` & `UP <uptime_seconds>`: Sampled every 5s (and on tick 0 for immediate dial population).
