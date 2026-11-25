use std::{
    env,
    ffi::OsString,
    fs,
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
    thread,
    time::Duration,
};

const O_RDONLY: i32 = 0;
const O_DIRECTORY: i32 = 0o200000;
const O_CLOEXEC: i32 = 0o2000000;

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
    fn getuid() -> u32;
    fn open(pathname: *const u8, flags: i32) -> i32;
    fn openat(dirfd: i32, pathname: *const u8, flags: i32) -> i32;
    fn read(fd: i32, buf: *mut u8, count: usize) -> isize;
    fn close(fd: i32) -> i32;
}

pub(crate) const SIGTERM: i32 = 15;
pub(crate) const SIGKILL: i32 = 9;

struct FdGuard(i32);

impl Drop for FdGuard {
    fn drop(&mut self) {
        if self.0 >= 0 {
            unsafe {
                let _ = close(self.0);
            }
        }
    }
}

pub(crate) fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let uid = unsafe { getuid() };
            let candidate = PathBuf::from(format!("/run/user/{uid}"));
            if candidate.is_dir() {
                candidate
            } else {
                PathBuf::from("/tmp")
            }
        })
}

#[inline]
pub(crate) fn pid_alive(pid: u32) -> bool {
    pid > 0 && unsafe { kill(pid as i32, 0) == 0 }
}

#[inline]
pub(crate) fn signal_pid(pid: u32, sig: i32) -> bool {
    pid > 0 && unsafe { kill(pid as i32, sig) == 0 }
}

/// Fast ASCII decimal parser avoiding UTF-8 validation and heap allocation.
#[inline]
fn parse_ascii_pid(bytes: &[u8]) -> Option<u32> {
    if bytes.is_empty() || bytes.len() > 10 {
        return None;
    }
    let mut acc = 0u32;
    for &b in bytes {
        if !b.is_ascii_digit() {
            return None;
        }
        acc = acc.checked_mul(10)?.checked_add((b - b'0') as u32)?;
    }
    (acc > 0).then_some(acc)
}

/// Read a relative `/proc/<pid>/<leaf>` file into a caller-provided stack buffer
/// via `openat` + `read`, performing zero heap allocations per PID.
#[inline]
fn read_proc_leaf<'a>(
    proc_dfd: i32,
    pid_bytes: &[u8],
    leaf: &[u8],
    path_buf: &mut [u8; 32],
    out_buf: &'a mut [u8],
) -> Option<&'a [u8]> {
    let need = pid_bytes.len() + 1 + leaf.len() + 1;
    if need > path_buf.len() {
        return None;
    }
    path_buf[..pid_bytes.len()].copy_from_slice(pid_bytes);
    path_buf[pid_bytes.len()] = b'/';
    let leaf_start = pid_bytes.len() + 1;
    path_buf[leaf_start..leaf_start + leaf.len()].copy_from_slice(leaf);
    path_buf[leaf_start + leaf.len()] = 0;

    // SAFETY: `path_buf` is NUL-terminated in-bounds, `out_buf` is valid writable
    // memory for `out_buf.len()` bytes, and `fd` is closed before returning.
    unsafe {
        let fd = openat(proc_dfd, path_buf.as_ptr(), O_RDONLY | O_CLOEXEC);
        if fd < 0 {
            return None;
        }
        let n = read(fd, out_buf.as_mut_ptr(), out_buf.len());
        let _ = close(fd);
        if n <= 0 {
            return None;
        }
        Some(&out_buf[..n as usize])
    }
}

/// Scan `/proc` using `openat` and stack buffers with zero per-PID heap allocations.
pub(crate) fn find_pids_by_name(exact_name: &str) -> Vec<u32> {
    let self_pid = std::process::id();
    let target = exact_name.as_bytes();
    let mut out = Vec::new();

    // SAFETY: `c"/proc"` is a static NUL-terminated C string.
    let proc_fd = unsafe {
        open(
            c"/proc".as_ptr().cast::<u8>(),
            O_RDONLY | O_DIRECTORY | O_CLOEXEC,
        )
    };
    if proc_fd < 0 {
        return out;
    }
    let _guard = FdGuard(proc_fd);

    let Ok(entries) = fs::read_dir("/proc") else {
        return out;
    };
    let mut path_buf = [0u8; 32];
    let mut comm_buf = [0u8; 64];
    let mut cmd_buf = [0u8; 512];

    for entry in entries.flatten() {
        let name_os = entry.file_name();
        let pid_bytes = name_os.as_bytes();
        let Some(pid) = parse_ascii_pid(pid_bytes) else {
            continue;
        };
        if pid == self_pid || !pid_alive(pid) {
            // `kill(pid, 0)` succeeds iff the process belongs to our UID (or root).
            continue;
        }
        if let Some(raw_comm) =
            read_proc_leaf(proc_fd, pid_bytes, b"comm", &mut path_buf, &mut comm_buf)
        {
            let comm = raw_comm.strip_suffix(b"\n").unwrap_or(raw_comm);
            if comm == target {
                out.push(pid);
                continue;
            }
        }
        if target.len() > 15 {
            if let Some(raw_cmd) =
                read_proc_leaf(proc_fd, pid_bytes, b"cmdline", &mut path_buf, &mut cmd_buf)
            {
                if let Some(first) = raw_cmd.split(|&b| b == 0).next() {
                    let base = first.rsplit(|&b| b == b'/').next().unwrap_or(first);
                    if base == target {
                        out.push(pid);
                    }
                }
            }
        }
    }
    out
}

/// True when any process owned by the current UID has exact `argv` matching `expected`.
pub(crate) fn any_cmdline_matches(expected: &[&str]) -> bool {
    let self_pid = std::process::id();
    // SAFETY: `c"/proc"` is a static NUL-terminated C string.
    let proc_fd = unsafe {
        open(
            c"/proc".as_ptr().cast::<u8>(),
            O_RDONLY | O_DIRECTORY | O_CLOEXEC,
        )
    };
    if proc_fd < 0 {
        return false;
    }
    let _guard = FdGuard(proc_fd);

    let Ok(entries) = fs::read_dir("/proc") else {
        return false;
    };
    let mut path_buf = [0u8; 32];
    let mut cmd_buf = [0u8; 1024];

    for entry in entries.flatten() {
        let name_os = entry.file_name();
        let pid_bytes = name_os.as_bytes();
        let Some(pid) = parse_ascii_pid(pid_bytes) else {
            continue;
        };
        if pid == self_pid || !pid_alive(pid) {
            continue;
        }
        let Some(raw) = read_proc_leaf(proc_fd, pid_bytes, b"cmdline", &mut path_buf, &mut cmd_buf)
        else {
            continue;
        };
        let trimmed = raw.strip_suffix(&[0]).unwrap_or(raw);
        let mut iter = trimmed.split(|&b| b == 0);
        let mut ok = true;
        for &exp in expected {
            let Some(actual) = iter.next() else {
                ok = false;
                break;
            };
            let exp_b = exp.as_bytes();
            if actual != exp_b {
                let base = actual.rsplit(|&b| b == b'/').next().unwrap_or(actual);
                if exp.contains('/') || base != exp_b {
                    ok = false;
                    break;
                }
            }
        }
        if ok && iter.next().is_none() {
            return true;
        }
    }
    false
}

pub(crate) fn stop_by_name(exact_name: &str, sig: i32, wait_ms: u64) -> bool {
    let pids = find_pids_by_name(exact_name);
    if pids.is_empty() {
        return true;
    }
    for &pid in &pids {
        let _ = signal_pid(pid, sig);
    }
    if wait_ms == 0 {
        return true;
    }
    let step = 25u64;
    let mut waited = 0u64;
    while waited < wait_ms {
        if find_pids_by_name(exact_name).is_empty() {
            return true;
        }
        thread::sleep(Duration::from_millis(step));
        waited += step;
    }
    find_pids_by_name(exact_name).is_empty()
}

pub(crate) fn which_in_path(bin: &str) -> Option<PathBuf> {
    if bin.contains('/') {
        let p = PathBuf::from(bin);
        return is_executable(&p).then_some(p);
    }
    let path_var: OsString = env::var_os("PATH")?;
    for dir in env::split_paths(&path_var) {
        let cand = dir.join(bin);
        if is_executable(&cand) {
            return Some(cand);
        }
    }
    None
}

pub(crate) fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path).is_ok_and(|m| m.is_file() && (m.permissions().mode() & 0o111) != 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn self_pid_is_alive_and_ascii_pid_parses() {
        assert!(pid_alive(std::process::id()));
        assert!(!pid_alive(0));
        assert_eq!(parse_ascii_pid(b"4291"), Some(4291));
        assert_eq!(parse_ascii_pid(b"self"), None);
    }
}
