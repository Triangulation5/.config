mod dbus;
mod net;
mod thumbs;

use std::env;
use std::ffi::{c_char, c_int, c_void, CString};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

// Linux ABI constants (x86_64 / aarch64)
const AF_NETLINK: c_int = 16;
const SOCK_RAW: c_int = 3;
const SOCK_CLOEXEC: c_int = 0x80000;
const NETLINK_KOBJECT_UEVENT: c_int = 15;
const IN_CLOEXEC: c_int = 0x80000;
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

fn parse_u64_flag(args: &[String], flag: &str, default: u64) -> u64 {
    let mut i = 0;
    while i + 1 < args.len() {
        if args[i] == flag {
            if let Ok(v) = args[i + 1].parse::<u64>() {
                return v;
            }
        }
        i += 1;
    }
    default
}

fn parse_str_flag<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    let mut i = 0;
    while i + 1 < args.len() {
        if args[i] == flag {
            return Some(args[i + 1].as_str());
        }
        i += 1;
    }
    None
}

// ============================================================================
// 1. Backlight event watcher (NETLINK_KOBJECT_UEVENT + fallback poll)
// ============================================================================

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

fn cmd_backlight_watch() {
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

    // Try event-driven netlink uevent socket first (0% CPU when idle, instant updates)
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
            let mut buf = [0u8; 4096];
            loop {
                let n = unsafe { recv(fd, buf.as_mut_ptr() as *mut c_void, buf.len(), 0) };
                if n <= 0 {
                    break;
                }
                let slice = &buf[..n as usize];
                if slice
                    .split(|&b| b == 0)
                    .any(|part| part == b"SUBSYSTEM=backlight")
                {
                    if !emit_if_changed(&mut out) {
                        break;
                    }
                }
            }
            unsafe { close(fd) };
            return;
        }
        unsafe { close(fd) };
    }

    // Fallback: zero-fork poll loop if netlink socket is unavailable
    loop {
        thread::sleep(Duration::from_secs(1));
        if !emit_if_changed(&mut out) {
            break;
        }
    }
}

// ============================================================================
// 2. Hyprland UNIX socket watchers (BarLayout, Fullscreen, Workspacerules)
// ============================================================================

fn hypr_socket_paths() -> Option<(PathBuf, PathBuf)> {
    let sig = env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    if sig.is_empty() {
        return None;
    }
    if let Ok(xdg) = env::var("XDG_RUNTIME_DIR") {
        let base = PathBuf::from(xdg).join("hypr").join(&sig);
        let s1 = base.join(".socket.sock");
        let s2 = base.join(".socket2.sock");
        if s1.exists() && s2.exists() {
            return Some((s1, s2));
        }
    }
    let base = PathBuf::from("/tmp/hypr").join(&sig);
    let s1 = base.join(".socket.sock");
    let s2 = base.join(".socket2.sock");
    if s1.exists() && s2.exists() {
        Some((s1, s2))
    } else {
        None
    }
}

fn hypr_query(sock1: &Path, cmd: &str) -> Option<String> {
    let mut stream = UnixStream::connect(sock1).ok()?;
    let _ = stream.set_read_timeout(Some(Duration::from_millis(1500)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(1500)));
    stream.write_all(cmd.as_bytes()).ok()?;
    let _ = stream.shutdown(Shutdown::Write);
    let mut resp = String::new();
    stream.read_to_string(&mut resp).ok()?;
    Some(compact_json_line(&resp))
}

/// Strip raw newlines outside strings (or replace CR/LF with space) so SplitParser
/// receives a single clean JSON line per update.
fn compact_json_line(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for ch in raw.chars() {
        match ch {
            '\n' | '\r' => out.push(' '),
            c => out.push(c),
        }
    }
    let trimmed = out.trim();
    if trimmed.is_empty() {
        "null".to_string()
    } else {
        trimmed.to_string()
    }
}

fn run_hypr_watcher<F>(events: &[&str], poll_ms: Option<u64>, debounce_ms: u64, mut emit: F)
where
    F: FnMut(&Path, &mut io::StdoutLock) -> bool,
{
    let (sock1, sock2) = match hypr_socket_paths() {
        Some(p) => p,
        None => std::process::exit(1),
    };

    let stream = match UnixStream::connect(&sock2) {
        Ok(s) => s,
        Err(_) => std::process::exit(1),
    };

    // Use a short read timeout so we can service debounce + optional fallback poll
    // without spawning extra threads.
    let timeout_ms = match poll_ms {
        Some(p) => p.min(250).max(40),
        None => 100,
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(timeout_ms)));
    let mut reader = BufReader::new(stream);

    let stdout = io::stdout();
    let mut out = stdout.lock();

    // Emit initial state immediately
    if !emit(&sock1, &mut out) {
        return;
    }

    let mut last_emit = Instant::now();
    let mut dirty_since: Option<Instant> = None;
    let mut line = String::new();

    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break, // Hyprland closed socket2
            Ok(_) => {
                if let Some((ev, _)) = line.split_once(">>") {
                    if events.iter().any(|&e| e == ev) && dirty_since.is_none() {
                        dirty_since = Some(Instant::now());
                    }
                }
            }
            Err(ref e)
                if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::TimedOut =>
            {
                // Timeout tick — check debounce & fallback poll below
            }
            Err(_) => break,
        }

        let now = Instant::now();
        let should_emit = if let Some(since) = dirty_since {
            now.duration_since(since) >= Duration::from_millis(debounce_ms)
        } else if let Some(p_ms) = poll_ms {
            now.duration_since(last_emit) >= Duration::from_millis(p_ms)
        } else {
            false
        };

        if should_emit {
            dirty_since = None;
            last_emit = now;
            if !emit(&sock1, &mut out) {
                break;
            }
        }
    }
}

fn cmd_hypr_barlayout(args: &[String]) {
    let interval_ms = parse_u64_flag(args, "--interval", 3000).max(500);
    let events = [
        "workspace",
        "workspacev2",
        "createworkspacev2",
        "destroyworkspacev2",
        "moveworkspacev2",
        "focusedmonv2",
        "openwindow",
        "closewindow",
        "movewindowv2",
        "configreloaded",
    ];
    run_hypr_watcher(&events, Some(interval_ms), 40, |sock1, out| {
        let ws = hypr_query(sock1, "j/workspaces").unwrap_or_else(|| "null".to_string());
        let opt =
            hypr_query(sock1, "j/getoption general:layout").unwrap_or_else(|| "null".to_string());
        writeln!(out, "{{\"workspaces\":{},\"layout\":{}}}", ws, opt).is_ok()
            && out.flush().is_ok()
    });
}

fn cmd_hypr_fullscreen() {
    let events = [
        "fullscreen",
        "workspacev2",
        "activewindowv2",
        "openwindow",
        "closewindow",
        "movewindowv2",
        "monitoraddedv2",
        "monitorremoved",
        "configreloaded",
    ];
    run_hypr_watcher(&events, None, 90, |sock1, out| {
        let mons = hypr_query(sock1, "j/monitors").unwrap_or_else(|| "null".to_string());
        let ws = hypr_query(sock1, "j/workspaces").unwrap_or_else(|| "null".to_string());
        writeln!(out, "{{\"monitors\":{},\"workspaces\":{}}}", mons, ws).is_ok()
            && out.flush().is_ok()
    });
}

fn cmd_hypr_workspacerules() {
    let events = [
        "createworkspacev2",
        "destroyworkspacev2",
        "moveworkspacev2",
        "renameworkspace",
        "monitoraddedv2",
        "monitorremoved",
        "configreloaded",
    ];
    run_hypr_watcher(&events, None, 50, |sock1, out| {
        let rules = hypr_query(sock1, "j/workspacerules").unwrap_or_else(|| "null".to_string());
        let ws = hypr_query(sock1, "j/workspaces").unwrap_or_else(|| "null".to_string());
        writeln!(out, "{{\"rules\":{},\"workspaces\":{}}}", rules, ws).is_ok()
            && out.flush().is_ok()
    });
}

// ============================================================================
// 3. Filesystem & /proc watchers (Downloads, RecEngine, Claude widget)
// ============================================================================

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
                        if best.as_ref().map_or(true, |(t, _)| mtime > *t) {
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

fn cmd_downloads_probe() {
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

fn cmd_stat_watch(args: &[String]) {
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

fn cmd_file_wait(args: &[String]) {
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
                        // Re-check after adding watch to close the race window
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

    // Fallback poll if parent dir didn't exist yet or inotify was unavailable
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

fn cmd_proc_watch(args: &[String]) {
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

fn parse_pair_i64(s: &str, key: &str) -> Option<(i64, i64)> {
    let idx = s.find(key)?;
    let rest = &s[idx + key.len()..];
    let lb = rest.find('[')?;
    let rb = rest[lb + 1..].find(']')?;
    let inner = &rest[lb + 1..lb + 1 + rb];
    let mut parts = inner.split(',');
    let a = parts.next()?.trim().parse::<i64>().ok()?;
    let b = parts.next()?.trim().parse::<i64>().ok()?;
    Some((a, b))
}

/// Native Hyprland client geometry -> slurp bridge (eliminates `sh`, `hyprctl`, `jq`).
fn cmd_hypr_slurp() {
    let (sock1, _) = match hypr_socket_paths() {
        Some(p) => p,
        None => std::process::exit(1),
    };
    let raw = match hypr_query(&sock1, "j/clients") {
        Some(r) => r,
        None => std::process::exit(1),
    };

    // Extract each client object's `at` and `size` arrays into `x,y wxh\n` lines
    let mut rects = String::new();
    let mut pos = 0usize;
    let bytes = raw.as_bytes();
    while pos < bytes.len() {
        if bytes[pos] == b'{' {
            let start = pos;
            let mut depth = 0i32;
            let mut in_str = false;
            let mut esc = false;
            while pos < bytes.len() {
                let b = bytes[pos];
                if in_str {
                    if esc {
                        esc = false;
                    } else if b == b'\\' {
                        esc = true;
                    } else if b == b'"' {
                        in_str = false;
                    }
                } else {
                    match b {
                        b'"' => in_str = true,
                        b'{' => depth += 1,
                        b'}' => {
                            depth -= 1;
                            if depth == 0 {
                                let obj = &raw[start..=pos];
                                if let (Some((x, y)), Some((w, h))) = (
                                    parse_pair_i64(obj, "\"at\""),
                                    parse_pair_i64(obj, "\"size\""),
                                ) {
                                    if w > 0 && h > 0 {
                                        use std::fmt::Write as _;
                                        let _ = writeln!(rects, "{},{} {}x{}", x, y, w, h);
                                    }
                                }
                                pos += 1;
                                break;
                            }
                        }
                        _ => {}
                    }
                }
                pos += 1;
            }
        } else {
            pos += 1;
        }
    }

    let mut child = match Command::new("slurp")
        .args(["-f", "%wx%h+%x+%y"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => std::process::exit(1),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(rects.as_bytes());
    }
    match child.wait_with_output() {
        Ok(out) => {
            if !out.stdout.is_empty() {
                let _ = io::stdout().write_all(&out.stdout);
                let _ = io::stdout().flush();
            }
            if !out.status.success() {
                std::process::exit(out.status.code().unwrap_or(1));
            }
        }
        Err(_) => std::process::exit(1),
    }
}

/// Persistent emoji index & matcher for `modules/launcher/Launcher.qml`.
/// Usage: emoji-match <path/to/emojis.js>
/// Protocol:
///   stdin:  <seq>\t<query>\n
///   stdout: {"seq":<seq>,"indices":[...]}\n
fn cmd_emoji_match(args: &[String]) {
    let path = match args.first() {
        Some(p) => Path::new(p),
        None => std::process::exit(2),
    };
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => std::process::exit(1),
    };

    let mut names: Vec<String> = Vec::with_capacity(1400);
    for line in content.lines() {
        if let Some(idx) = line.find("n: \"") {
            let rest = &line[idx + 4..];
            if let Some(end) = rest.find('"') {
                names.push(rest[..end].to_ascii_lowercase());
            }
        }
    }

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let mut line = String::new();
    let mut reader = BufReader::new(stdin.lock());

    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
                let Some((seq_s, q_raw)) = trimmed.split_once('\t') else {
                    continue;
                };
                let seq: u64 = seq_s.parse().unwrap_or(0);
                let q = q_raw.trim().to_ascii_lowercase();

                let mut prefix: Vec<usize> = Vec::new();
                let mut word: Vec<usize> = Vec::new();
                let mut sub: Vec<usize> = Vec::new();

                if q.is_empty() {
                    prefix.extend(0..names.len());
                } else {
                    for (i, name) in names.iter().enumerate() {
                        if name.starts_with(&q) {
                            prefix.push(i);
                        } else if let Some(pos) = name.find(&q) {
                            let prev = name.as_bytes()[pos - 1];
                            if prev == b' ' || prev == b'-' || prev == b'(' {
                                word.push(i);
                            } else {
                                sub.push(i);
                            }
                        }
                    }
                }

                let _ = write!(out, "{{\"seq\":{},\"indices\":[", seq);
                let mut first = true;
                for idx in prefix.into_iter().chain(word).chain(sub) {
                    if !first {
                        let _ = write!(out, ",");
                    }
                    first = false;
                    let _ = write!(out, "{}", idx);
                }
                if writeln!(out, "]}}").is_err() || out.flush().is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!(
            "Usage: silhouette_watchers <backlight-watch|hypr-barlayout|hypr-fullscreen|hypr-workspacerules|downloads-probe|stat-watch|file-wait|proc-watch> [args]"
        );
        std::process::exit(2);
    }
    match args[1].as_str() {
        "backlight-watch" => cmd_backlight_watch(),
        "hypr-barlayout" => cmd_hypr_barlayout(&args[2..]),
        "hypr-fullscreen" => cmd_hypr_fullscreen(),
        "hypr-workspacerules" => cmd_hypr_workspacerules(),
        "downloads-probe" => cmd_downloads_probe(),
        "stat-watch" => cmd_stat_watch(&args[2..]),
        "file-wait" => cmd_file_wait(&args[2..]),
        "proc-watch" => cmd_proc_watch(&args[2..]),
        "logind-watch" => dbus::cmd_logind_watch(),
        "net-speedtest" => net::cmd_net_speedtest(&args[2..]),
        "net-geolocate" => net::cmd_net_geolocate(),
        "net-fetch" => net::cmd_net_fetch(&args[2..]),
        "thumbs-walls" => thumbs::cmd_thumbs_walls(&args[2..]),
        "thumbs-cliphist" => thumbs::cmd_thumbs_cliphist(&args[2..]),
        "thumbs-rec" => thumbs::cmd_thumbs_rec(&args[2..]),
        "hotspot-state" => thumbs::cmd_hotspot_state(&args[2..]),
        "hypr-slurp" => cmd_hypr_slurp(),
        "emoji-match" => cmd_emoji_match(&args[2..]),
        "net-local-ip" => net::cmd_net_local_ip(),
        "cursor-themes" => thumbs::cmd_cursor_themes(),
        "clip-copy" => thumbs::cmd_clip_copy(&args[2..]),
        "clip-delete" => thumbs::cmd_clip_delete(&args[2..]),
        "write-file" => thumbs::cmd_write_file(&args[2..]),
        other => {
            eprintln!("Unknown subcommand: {}", other);
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_json_strips_newlines() {
        assert_eq!(compact_json_line("{\n  \"a\": 1\r\n}\n"), "{   \"a\": 1  }");
        assert_eq!(compact_json_line("   \n\t "), "null");
    }

    #[test]
    fn parse_pair_i64_extracts_coords() {
        let obj = r#"{"at": [120, -40], "size": [1920, 1080]}"#;
        assert_eq!(parse_pair_i64(obj, "\"at\""), Some((120, -40)));
        assert_eq!(parse_pair_i64(obj, "\"size\""), Some((1920, 1080)));
        assert_eq!(parse_pair_i64(obj, "\"missing\""), None);
    }

    #[test]
    fn rec_cmdline_matcher_covers_all_backends() {
        assert!(matches_rec_cmdline("/usr/bin/gpu-screen-recorder\0-w\0screen"));
        assert!(matches_rec_cmdline("gpu-screen-recorder\0-f\060"));
        assert!(matches_rec_cmdline("python3\0/home/u/portal_capture.py\0--output\0a.mp4"));
        assert!(matches_rec_cmdline("/path/framepump-x86_64\0--portal\0--output\0a.mp4"));
        assert!(!matches_rec_cmdline("/path/framepump-x86_64\0--frame-bytes\0100"));
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
