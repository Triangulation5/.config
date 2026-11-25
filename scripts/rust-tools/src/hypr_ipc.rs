use crate::proc_util::{runtime_dir, which_in_path};
use serde_json::Value;
use std::{
    env,
    io::{Read, Write},
    net::Shutdown,
    os::unix::{net::UnixStream, process::CommandExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};

fn is_system_hyprctl(path: &Path) -> bool {
    matches!(
        path.parent().and_then(Path::to_str),
        Some(
            "/usr/bin"
                | "/bin"
                | "/usr/local/bin"
                | "/sbin"
                | "/usr/sbin"
                | "/run/current-system/sw/bin"
                | "/usr/pkg/bin"
        )
    )
}

/// Returns `Some(path)` when a non-system `hyprctl` shim precedes the real binary
/// on `PATH` (e.g. test harnesses), so tests can intercept IPC calls cleanly.
fn custom_hyprctl_shim() -> Option<PathBuf> {
    if env::var_os("SILHOUETTE_FORCE_HYPRCTL").is_some() {
        return which_in_path("hyprctl");
    }
    let found = which_in_path("hyprctl")?;
    (!is_system_hyprctl(&found)).then_some(found)
}

pub(crate) fn socket_path() -> Option<PathBuf> {
    if custom_hyprctl_shim().is_some() {
        return None;
    }
    let sig = env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    if sig.is_empty() {
        return None;
    }
    let primary = runtime_dir().join("hypr").join(&sig).join(".socket.sock");
    if primary.exists() {
        return Some(primary);
    }
    let fallback = PathBuf::from("/tmp/hypr").join(&sig).join(".socket.sock");
    fallback.exists().then_some(fallback)
}

pub(crate) fn raw_request(cmd: &str) -> Option<String> {
    let sock = socket_path()?;
    let mut stream = UnixStream::connect(sock).ok()?;
    let _ = stream.set_read_timeout(Some(Duration::from_millis(2000)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(2000)));
    stream.write_all(cmd.as_bytes()).ok()?;
    let _ = stream.shutdown(Shutdown::Write);
    let mut buf = String::new();
    stream.read_to_string(&mut buf).ok()?;
    Some(buf)
}

/// Zero-heap-allocation stack socket request for tiny payloads (such as
/// `j/activeworkspace` on every keybind press).
pub(crate) fn raw_request_stack<'a>(cmd: &[u8], buf: &'a mut [u8]) -> Option<&'a [u8]> {
    let sock = socket_path()?;
    let mut stream = UnixStream::connect(sock).ok()?;
    let _ = stream.set_read_timeout(Some(Duration::from_millis(1000)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(1000)));
    stream.write_all(cmd).ok()?;
    let _ = stream.shutdown(Shutdown::Write);
    let mut filled = 0usize;
    while filled < buf.len() {
        match stream.read(&mut buf[filled..]) {
            Ok(0) => break,
            Ok(n) => filled += n,
            Err(_) => return None,
        }
    }
    Some(&buf[..filled])
}

/// Extract a top-level string field (e.g. `"monitor": "eDP-1"`) from a stack
/// JSON buffer without building a `serde_json::Value` tree.
pub(crate) fn extract_json_str_fast<'a>(json: &'a [u8], needle: &[u8]) -> Option<&'a str> {
    let pos = json.windows(needle.len()).position(|w| w == needle)?;
    let mut rest = &json[pos + needle.len()..];
    while let Some((&b, tail)) = rest.split_first() {
        if matches!(b, b' ' | b'\t' | b'\n' | b'\r' | b':') {
            rest = tail;
        } else {
            break;
        }
    }
    let rest = rest.strip_prefix(b"\"")?;
    let end = rest.iter().position(|&b| b == b'"')?;
    if rest[..end].contains(&b'\\') {
        return None;
    }
    std::str::from_utf8(&rest[..end]).ok()
}

pub(crate) fn parse_json_payload(raw: &str) -> Option<Value> {
    let start = raw.find(['[', '{'])?;
    serde_json::from_str(&raw[start..]).ok()
}

pub(crate) fn query_json(noun: &str) -> Option<Value> {
    if let Some(resp) = raw_request(&format!("j/{noun}")) {
        if let Some(val) = parse_json_payload(&resp) {
            return Some(val);
        }
    }
    let bin = custom_hyprctl_shim().unwrap_or_else(|| PathBuf::from("hyprctl"));
    let out = Command::new(bin)
        .args([noun, "-j"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    parse_json_payload(&String::from_utf8_lossy(&out.stdout))
}

pub(crate) fn get_option_json(opt: &str) -> Option<Value> {
    if let Some(resp) = raw_request(&format!("j/getoption {opt}")) {
        if let Some(val) = parse_json_payload(&resp) {
            return Some(val);
        }
    }
    let bin = custom_hyprctl_shim().unwrap_or_else(|| PathBuf::from("hyprctl"));
    let out = Command::new(bin)
        .args(["getoption", opt, "-j"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| parse_json_payload(&String::from_utf8_lossy(&out.stdout)))
        .flatten()
}

/// Fetch `N` Hyprland options in a single pipelined `[[BATCH]]` socket round-trip,
/// falling back to individual queries only if batch framing isn't available.
pub(crate) fn get_options_batch<const N: usize>(opts: [&str; N]) -> [Option<Value>; N] {
    let mut batch_cmd = String::from("[[BATCH]]");
    for (idx, opt) in opts.iter().enumerate() {
        if idx > 0 {
            batch_cmd.push(';');
        }
        batch_cmd.push_str("j/getoption ");
        batch_cmd.push_str(opt);
    }
    if let Some(raw) = raw_request(&batch_cmd) {
        let mut results: [Option<Value>; N] = std::array::from_fn(|_| None);
        let mut stream = serde_json::Deserializer::from_str(&raw).into_iter::<Value>();
        let mut count = 0usize;
        for slot in &mut results {
            if let Some(Ok(val)) = stream.next() {
                *slot = Some(val);
                count += 1;
            }
        }
        if count == N {
            return results;
        }
    }
    std::array::from_fn(|i| get_option_json(opts[i]))
}

pub(crate) fn dispatch(arg: &str) -> bool {
    if let Some(resp) = raw_request(&format!("dispatch {arg}")) {
        let trimmed = resp.trim();
        return trimmed.is_empty() || trimmed == "ok";
    }
    let bin = custom_hyprctl_shim().unwrap_or_else(|| PathBuf::from("hyprctl"));
    Command::new(bin)
        .args(["dispatch", arg])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

pub(crate) fn eval(expr: &str) -> bool {
    if let Some(resp) = raw_request(&format!("eval {expr}")) {
        return resp.trim() == "ok";
    }
    let bin = custom_hyprctl_shim().unwrap_or_else(|| PathBuf::from("hyprctl"));
    Command::new(bin)
        .args(["eval", expr])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

pub(crate) fn reload() -> bool {
    if let Some(resp) = raw_request("reload") {
        let trimmed = resp.trim();
        return trimmed.is_empty() || trimmed == "ok";
    }
    let bin = custom_hyprctl_shim().unwrap_or_else(|| PathBuf::from("hyprctl"));
    Command::new(bin)
        .arg("reload")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

pub(crate) fn exec_qs_ipc(ipc_args: &[&str]) -> bool {
    for candidate in ["qs", "quickshell"] {
        if let Some(bin_path) = which_in_path(candidate) {
            let err = Command::new(bin_path)
                .args(["-c", "silhouette-shell", "ipc", "call"])
                .args(ipc_args)
                .exec();
            eprintln!("hypr-ipc: failed to exec {candidate}: {err}");
            return false;
        }
    }
    false
}

pub(crate) fn notify_desktop(title: &str, message: &str, urgency: &str, icon: Option<&str>) {
    let level = env::var("LOG_LEVEL").unwrap_or_else(|_| "info".to_string());
    if level == "quiet" || message.is_empty() {
        return;
    }
    let send_bin = env::var("NOTIFY_SEND").unwrap_or_else(|_| "notify-send".to_string());
    let app = env::var("NOTIFY_APPNAME").unwrap_or_else(|_| "Silhouette".to_string());
    let default_icon = env::var("NOTIFY_ICON").unwrap_or_else(|_| "background-change".to_string());
    let icon_val = icon.unwrap_or(&default_icon);
    let _ = Command::new(send_bin)
        .args(["-u", urgency, "-i", icon_val, "-a", &app, title, message])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}
