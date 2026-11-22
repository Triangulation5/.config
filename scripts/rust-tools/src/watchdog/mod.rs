mod launcher;
mod probe;

use std::{
    env,
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::{Duration, Instant},
};

const SIGUSR1: i32 = 10;
const TICK_UNLOCKED_MS: u64 = 1000;
const TICK_LOCKED_MS: u64 = 100;
const CEILING_UNLOCKED: u64 = 60;
const CEILING_LOCKED: u64 = 600;
const WAKE_SLICE_MS: u64 = 50;

static POKED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_sigusr1(_sig: i32) {
    POKED.store(true, Ordering::SeqCst);
}

extern "C" {
    fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
}

fn install_sigusr1() {
    // SAFETY: `handle_sigusr1` only performs an atomic store, which is async-signal-safe.
    unsafe {
        signal(SIGUSR1, handle_sigusr1);
    }
}

/// Sleep for `total`, waking early if `SIGUSR1` sets `POKED`.
fn interruptible_sleep(total: Duration) {
    let start = Instant::now();
    while !POKED.load(Ordering::SeqCst) {
        let elapsed = start.elapsed();
        if elapsed >= total {
            break;
        }
        let remaining = total - elapsed;
        thread::sleep(remaining.min(Duration::from_millis(WAKE_SLICE_MS)));
    }
}

fn default_scripts_dir() -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".config/scripts")
}

pub(crate) fn run(name: &str, scripts_dir: Option<&Path>) -> bool {
    if name.is_empty() {
        eprintln!("watchdog: missing shell config name");
        return false;
    }

    install_sigusr1();

    let runtime = PathBuf::from(env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string()));
    let lock_path = runtime.join(format!("{name}-watchdog.lock"));
    let Some(_lock_guard) = probe::acquire_lock(&lock_path) else {
        // Another supervisor already holds the lock; exit cleanly.
        return true;
    };

    let scripts_dir = scripts_dir
        .map(Path::to_path_buf)
        .unwrap_or_else(default_scripts_dir);
    let lock_marker = runtime.join("silhouette-locked");

    let mut shell_pid: Option<u32> = None;
    let mut tick_count: u64 = 0;

    loop {
        let locked = probe::is_locked(&lock_marker);
        let (step, span, poll_ticks) = if locked {
            (Duration::from_millis(TICK_LOCKED_MS), CEILING_LOCKED, 150)
        } else {
            (Duration::from_millis(TICK_UNLOCKED_MS), CEILING_UNLOCKED, 15)
        };

        let poked = POKED.swap(false, Ordering::SeqCst);
        let alive = shell_pid.is_some_and(probe::is_pid_alive);

        if !poked && tick_count % span != 0 && alive {
            // Fast path: process is alive, zero forks.
        } else if locked && !alive {
            // Dead while locked: skip full IPC probe to minimize exposed window.
            launcher::launch_shell(name, &scripts_dir, step, poll_ticks);
            shell_pid = probe::resolve_instance(&runtime);
        } else {
            if !probe::full_ipc_probe(name) {
                launcher::launch_shell(name, &scripts_dir, step, poll_ticks);
            }
            if !shell_pid.is_some_and(probe::is_pid_alive) {
                shell_pid = probe::resolve_instance(&runtime);
            }
        }

        interruptible_sleep(step);
        tick_count = tick_count.wrapping_add(1);
    }
}
