use crate::parse_u64_flag;
use std::env;
use std::fmt::Write as _;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

static HYPRLAND_SOCKETS: OnceLock<Option<(PathBuf, PathBuf)>> = OnceLock::new();

pub(crate) fn hypr_socket_paths() -> Option<(PathBuf, PathBuf)> {
    HYPRLAND_SOCKETS
        .get_or_init(|| {
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
        })
        .clone()
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

/// Strip raw newlines so SplitParser receives a single clean JSON line per update.
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

    let timeout_ms = match poll_ms {
        Some(p) => p.clamp(40, 250),
        None => 100,
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(timeout_ms)));
    let mut reader = BufReader::new(stream);

    let stdout = io::stdout();
    let mut out = stdout.lock();

    if !emit(&sock1, &mut out) {
        return;
    }

    let mut last_emit = Instant::now();
    let mut dirty_since: Option<Instant> = None;
    let mut line = String::new();

    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                if let Some((ev, _)) = line.split_once(">>") {
                    if events.contains(&ev) && dirty_since.is_none() {
                        dirty_since = Some(Instant::now());
                    }
                }
            }
            Err(ref e)
                if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::TimedOut =>
            {
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

pub fn cmd_hypr_barlayout(args: &[String]) {
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

pub fn cmd_hypr_fullscreen() {
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

pub fn cmd_hypr_workspacerules() {
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
pub fn cmd_hypr_slurp() {
    let (sock1, _) = match hypr_socket_paths() {
        Some(p) => p,
        None => std::process::exit(1),
    };
    let raw = match hypr_query(&sock1, "j/clients") {
        Some(r) => r,
        None => std::process::exit(1),
    };

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
}
