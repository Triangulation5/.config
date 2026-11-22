use std::{
    fs::{self, File},
    os::unix::{fs::MetadataExt, net::UnixStream},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::SystemTime,
};

/// Fast syscall check: `/proc/<pid>` exists while the process is alive.
pub(crate) fn is_pid_alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    Path::new(&format!("/proc/{pid}")).is_dir()
}

/// Read `$XDG_RUNTIME_DIR/silhouette-locked` ("1" while locked).
pub(crate) fn is_locked(lock_marker: &Path) -> bool {
    fs::read_to_string(lock_marker)
        .map(|s| s.trim() == "1")
        .unwrap_or(false)
}

/// Full IPC health probe (`qs -c <name> ipc show`).
pub(crate) fn full_ipc_probe(name: &str) -> bool {
    Command::new("qs")
        .args(["-c", name, "ipc", "show"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// Resolve the live quickshell instance PID by connecting directly to its
/// newest accepting Unix socket and matching its directory `(dev, ino)`
/// against `$runtime/quickshell/by-pid/<pid>`.
pub(crate) fn resolve_instance(runtime: &Path) -> Option<u32> {
    let by_path = runtime.join("quickshell/by-path");
    let by_pid = runtime.join("quickshell/by-pid");

    let mut sockets: Vec<(SystemTime, PathBuf)> = Vec::new();
    let hash_dirs = fs::read_dir(&by_path).ok()?;
    for hash_entry in hash_dirs.flatten() {
        let Ok(inst_dirs) = fs::read_dir(hash_entry.path()) else {
            continue;
        };
        for inst_entry in inst_dirs.flatten() {
            let sock = inst_entry.path().join("ipc.sock");
            if let Ok(meta) = fs::metadata(&sock) {
                let mtime = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
                sockets.push((mtime, sock));
            }
        }
    }

    // Newest sockets first, matching `ls -1t`.
    sockets.sort_unstable_by(|a, b| b.0.cmp(&a.0));

    for (_, sock) in sockets {
        if UnixStream::connect(&sock).is_err() {
            continue;
        }
        let Some(inst_dir) = sock.parent() else {
            continue;
        };
        let Ok(inst_meta) = fs::metadata(inst_dir) else {
            continue;
        };
        let target_id = (inst_meta.dev(), inst_meta.ino());

        let Ok(pid_entries) = fs::read_dir(&by_pid) else {
            continue;
        };
        for pid_entry in pid_entries.flatten() {
            let path = pid_entry.path();
            if let Ok(meta) = fs::metadata(&path) {
                if (meta.dev(), meta.ino()) == target_id {
                    if let Some(pid_str) = pid_entry.file_name().to_str() {
                        if let Ok(pid) = pid_str.parse::<u32>() {
                            return Some(pid);
                        }
                    }
                }
            }
        }
    }

    None
}

/// Acquire a non-blocking exclusive lock file for this watchdog instance.
/// Rust opens files with `O_CLOEXEC` on Unix, so spawned children never inherit it.
pub(crate) fn acquire_lock(lock_path: &Path) -> Option<File> {
    use fs2::FileExt;
    let file = fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(lock_path)
        .ok()?;
    file.try_lock_exclusive().ok()?;
    Some(file)
}
