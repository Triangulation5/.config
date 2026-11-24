use crate::{parse_str_flag, parse_u64_flag};
use std::env;
use std::ffi::{c_char, c_int, c_void, CString};
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, SystemTime};

// Linux ABI constants (x86_64 / aarch64)
const AF_NETLINK: c_int = 16;
const SOCK_RAW: c_int = 3;
const SOCK_CLOEXEC: c_int = 0x80000;
const NETLINK_KOBJECT_UEVENT: c_int = 15;
const IN_CLOEXEC: c_int = 0x80000;
const IN_MODIFY: u32 = 0x0000_0002;
const IN_CREATE: u32 = 0x0000_0100;
const IN_MOVED_TO: u32 = 0x0000_0080;
const IN_CLOSE_WRITE: u32 = 0x0000_0008;

#[repr(C)]
struct SockAddrNl {
    nl_family: u16,
    nl_pad: u16,
    nl_pid: u32,
    nl_groups: u32,
}

extern "C" {
    fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    fn bind(sockfd: c_int, addr: *const SockAddrNl, addrlen: u32) -> c_int;
    fn recv(sockfd: c_int, buf: *mut c_void, len: usize, flags: c_int) -> isize;
    fn close(fd: c_int) -> c_int;
    fn inotify_init1(flags: c_int) -> c_int;
    fn inotify_add_watch(fd: c_int, pathname: *const c_char, mask: u32) -> c_int;
    fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
}

fn find_backlight_device() -> Option<PathBuf> {
    let mut dirs: Vec<PathBuf> = fs::read_dir("/sys/class/backlight")
        .ok()?
        .flatten()
        .map(|e| e.path())
        .collect();
    dirs.sort();
    dirs.into_iter().next()
}

fn read_u64_file(path: &Path) -> Option<u64> {
    fs::read_to_string(path).ok()?.trim().parse::<u64>().ok()
}

/// Event-driven backlight monitor via NETLINK_KOBJECT_UEVENT with inotify fallback.
pub fn cmd_backlight_watch() {
    let dev = match find_backlight_device() {
        Some(d) => d,
        None => return,
    };
    let max_path = dev.join("max_brightness");
    let cur_path = dev.join("brightness");
    let max_val = match read_u64_file(&max_path) {
        Some(v) if v > 0 => v,
        _ => return,
    };

    let stdout = io::stdout();
    let mut out = stdout.lock();
    let mut last_val: Option<u64> = None;

    let mut emit_if_changed = |out: &mut io::StdoutLock| -> bool {
        if let Some(cur) = read_u64_file(&cur_path) {
            if last_val != Some(cur) {
                let pct = (cur.saturating_mul(100)) / max_val;
                if writeln!(out, "{}", pct).is_err() || out.flush().is_err() {
                    return false;
                }
                last_val = Some(cur);
            }
        }
        true
    };

    if !emit_if_changed(&mut out) {
        return;
    }

    let mut buf = [0u8; 4096];

    let fd = unsafe { socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT) };
    if fd >= 0 {
        let addr = SockAddrNl {
            nl_family: AF_NETLINK as u16,
            nl_pad: 0,
            nl_pid: 0,
            nl_groups: 1,
        };
        let bound = unsafe { bind(fd, &addr, std::mem::size_of::<SockAddrNl>() as u32) };
        if bound == 0 {
            loop {
                let n = unsafe { recv(fd, buf.as_mut_ptr() as *mut c_void, buf.len(), 0) };
                if n <= 0 {
                    break;
                }
                let slice = &buf[..n as usize];
                if slice
                    .split(|&b| b == 0)
                    .any(|part| part == b"SUBSYSTEM=backlight")
                    && !emit_if_changed(&mut out)
                {
                    break;
                }
            }
            unsafe { close(fd) };
            return;
        }
        unsafe { close(fd) };
    }

    let fd = unsafe { inotify_init1(IN_CLOEXEC) };
    if fd < 0 {
        return;
    }
    let c_path = match CString::new(cur_path.as_os_str().as_bytes()) {
        Ok(p) => p,
        Err(_) => {
            unsafe { close(fd) };
            return;
        }
    };
    let wd = unsafe { inotify_add_watch(fd, c_path.as_ptr(), IN_MODIFY | IN_CLOSE_WRITE) };
    if wd >= 0 {
        loop {
            let n = unsafe { read(fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
            if n <= 0 {
                break;
            }
            if !emit_if_changed(&mut out) {
                break;
            }
        }
    }
    unsafe { close(fd) };
}

fn scan_downloads_json(dir: &Path, depth: u8, best: &mut Option<(SystemTime, PathBuf)>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let ft = match entry.file_type() {
            Ok(t) => t,
            Err(_) => continue,
        };
        if ft.is_file() {
            if entry.file_name() == "downloads.json" {
                if let Ok(meta) = entry.metadata() {
                    if let Ok(mtime) = meta.modified() {
                        if best.as_ref().is_none_or(|(t, _)| mtime > *t) {
                            *best = Some((mtime, path));
                        }
                    }
                }
            }
        } else if ft.is_dir() && depth < 2 {
            scan_downloads_json(&path, depth + 1, best);
        }
    }
}

pub fn cmd_downloads_probe() {
    let home = match env::var("HOME") {
        Ok(h) if !h.is_empty() => PathBuf::from(h),
        _ => return,
    };
    let roots = [
        home.join(".mozilla/firefox"),
        home.join(".config/mozilla/firefox"),
        home.join(".var/app/org.mozilla.firefox/.mozilla/firefox"),
        home.join("snap/firefox/common/.mozilla/firefox"),
    ];
    let mut best: Option<(SystemTime, PathBuf)> = None;
    for root in &roots {
        if root.is_dir() {
            scan_downloads_json(root, 1, &mut best);
        }
    }
    if let Some((_, path)) = best {
        println!("{}", path.display());
    }
}

pub fn cmd_stat_watch(args: &[String]) {
    let path = match args.first() {
        Some(p) => PathBuf::from(p),
        None => return,
    };
    let interval_ms = parse_u64_flag(args, "--interval", 1000).max(200);
    let sleep_dur = Duration::from_millis(interval_ms);

    let stdout = io::stdout();
    let mut out = stdout.lock();
    loop {
        let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        if writeln!(out, "{}", size).is_err() || out.flush().is_err() {
            break;
        }
        thread::sleep(sleep_dur);
    }
}

pub fn cmd_file_wait(args: &[String]) {
    let path = match args.first() {
        Some(p) => PathBuf::from(p),
        None => return,
    };
    if path.exists() {
        println!("yes");
        return;
    }

    if let Some(parent) = path.parent() {
        if parent.is_dir() {
            if let Ok(c_parent) = CString::new(parent.to_string_lossy().as_bytes()) {
                let fd = unsafe { inotify_init1(IN_CLOEXEC) };
                if fd >= 0 {
                    let wd = unsafe {
                        inotify_add_watch(
                            fd,
                            c_parent.as_ptr(),
                            IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE,
                        )
                    };
                    if wd >= 0 {
                        if path.exists() {
                            unsafe { close(fd) };
                            println!("yes");
                            return;
                        }
                        let mut buf = [0u8; 4096];
                        loop {
                            let n =
                                unsafe { read(fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
                            if n <= 0 {
                                break;
                            }
                            if path.exists() {
                                unsafe { close(fd) };
                                println!("yes");
                                return;
                            }
                        }
                    }
                    unsafe { close(fd) };
                }
            }
        }
    }

    let interval_ms = parse_u64_flag(args, "--interval", 250).max(50);
    let sleep_dur = Duration::from_millis(interval_ms);
    loop {
        if path.exists() {
            println!("yes");
            return;
        }
        thread::sleep(sleep_dur);
    }
}

fn matches_rec_cmdline(cmdline: &str) -> bool {
    let mut is_framepump = false;
    let mut is_portal = false;
    for tok in cmdline.split('\0') {
        if tok.is_empty() {
            continue;
        }
        let base = tok.rsplit('/').next().unwrap_or(tok);
        if base == "gpu-screen-recorder" || tok.contains("portal_capture.py") {
            return true;
        }
        if base == "framepump" || base.starts_with("framepump-") {
            is_framepump = true;
        } else if tok == "--portal" {
            is_portal = true;
        }
    }
    is_framepump && is_portal
}

fn matches_claude_cmdline(cmdline: &str) -> bool {
    for tok in cmdline.split('\0') {
        if tok.is_empty() {
            continue;
        }
        for sub in tok.split_whitespace() {
            let trimmed = sub.trim_end_matches('/');
            let base = trimmed.rsplit('/').next().unwrap_or(trimmed);
            if base.eq_ignore_ascii_case("claude") || base.eq_ignore_ascii_case("claude-code") {
                return true;
            }
        }
    }
    false
}

fn count_matching_procs(mode: &str) -> usize {
    let self_pid = std::process::id();
    let entries = match fs::read_dir("/proc") {
        Ok(e) => e,
        Err(_) => return 0,
    };
    let mut count = 0usize;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        let pid: u32 = match name_str.parse() {
            Ok(p) if p != self_pid => p,
            _ => continue,
        };
        let cmdline_path = format!("/proc/{}/cmdline", pid);
        let bytes = match fs::read(cmdline_path) {
            Ok(b) if !b.is_empty() => b,
            _ => continue,
        };
        let cmdline = String::from_utf8_lossy(&bytes);
        let matched = match mode {
            "rec" => matches_rec_cmdline(&cmdline),
            "claude" => matches_claude_cmdline(&cmdline),
            _ => false,
        };
        if matched {
            count += 1;
        }
    }
    count
}

pub fn cmd_proc_watch(args: &[String]) {
    let mode = match parse_str_flag(args, "--mode") {
        Some(m) => m.to_string(),
        None => return,
    };
    let interval_ms = parse_u64_flag(args, "--interval", 1000).max(250);
    let sleep_dur = Duration::from_millis(interval_ms);

    let stdout = io::stdout();
    let mut out = stdout.lock();
    loop {
        let n = count_matching_procs(&mode);
        if writeln!(out, "COUNT {}", n).is_err() || out.flush().is_err() {
            break;
        }
        thread::sleep(sleep_dur);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rec_cmdline_matcher_covers_all_backends() {
        assert!(matches_rec_cmdline("/usr/bin/gpu-screen-recorder\0-w\0screen"));
        assert!(matches_rec_cmdline("gpu-screen-recorder\0-f\x0060"));
        assert!(matches_rec_cmdline("python3\0/home/u/portal_capture.py\0--output\0a.mp4"));
        assert!(matches_rec_cmdline("/path/framepump-x86_64\0--portal\0--output\0a.mp4"));
        assert!(!matches_rec_cmdline("/path/framepump-x86_64\0--frame-bytes\x00100"));
        assert!(!matches_rec_cmdline("ffmpeg\0-i\0foo.mp4"));
    }

    #[test]
    fn claude_cmdline_matcher_avoids_false_positives() {
        assert!(matches_claude_cmdline("node\0/usr/local/bin/claude\0--help"));
        assert!(matches_claude_cmdline("/opt/bin/claude-code\0"));
        assert!(matches_claude_cmdline("CLAUDE\0"));
        assert!(!matches_claude_cmdline("vim\0claudette.txt"));
        assert!(!matches_claude_cmdline("bash\0-c\0echo hello"));
    }
}
