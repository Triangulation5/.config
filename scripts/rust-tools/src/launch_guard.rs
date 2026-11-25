use crate::apps;
use std::{
    env,
    ffi::OsString,
    io::{ErrorKind, Read, Write},
    path::Path,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

const WINDOW_SECS: u64 = 5;
const STDERR_CAP_BYTES: usize = 65_536;

fn maybe_heal_appimage(cmd: &OsString) -> Option<OsString> {
    let s = cmd.to_str()?;
    if Path::new(s).is_file() {
        return None;
    }
    if !s.to_ascii_lowercase().ends_with(".appimage") {
        return None;
    }
    let out = env::current_exe()
        .ok()
        .and_then(|exe| {
            Command::new(exe)
                .args(["appimage-install", "heal", s])
                .stdin(Stdio::null())
                .stderr(Stdio::null())
                .output()
                .ok()
        })
        .filter(|o| o.status.success())?;
    let healed = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (!healed.is_empty() && Path::new(&healed).is_file()).then(|| OsString::from(healed))
}

fn drain_capped<R: Read>(mut reader: R, cap: usize) -> Vec<u8> {
    let mut captured = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        match reader.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => {
                if captured.len() < cap {
                    let room = cap - captured.len();
                    let take = room.min(n);
                    captured.extend_from_slice(&chunk[..take]);
                }
            }
            Err(err) if err.kind() == ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
    captured
}

fn tail_non_blank_lines(text: &str, count: usize) -> String {
    let non_blank: Vec<&str> = text
        .lines()
        .filter(|line| !line.trim().is_empty())
        .collect();
    let start = non_blank.len().saturating_sub(count);
    non_blank[start..].join("\n")
}

fn notify_and_copy(name: &str, icon: &str, rc: i32, err_body: &str) {
    let display_err = if err_body.is_empty() {
        "(no output)"
    } else {
        err_body
    };
    let tail3 = tail_non_blank_lines(display_err, 3);
    let summary = format!("{name} failed (exit {rc})");

    let mut cmd = Command::new("notify-send");
    cmd.args(["-u", "critical", "-a", "SilhouetteShell"]);
    if !icon.is_empty() {
        cmd.args(["-i", icon]);
    }
    cmd.args(["-A", "copy=Copy", &summary, &tail3]);
    cmd.stdin(Stdio::null()).stderr(Stdio::null());

    let Ok(out) = cmd.output() else {
        return;
    };
    let picked = String::from_utf8_lossy(&out.stdout);
    if picked.trim() == "copy" {
        if let Ok(mut clip) = Command::new("wl-copy")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            if let Some(mut stdin) = clip.stdin.take() {
                let _ = write!(stdin, "{name}: exit {rc}\n{display_err}\n");
            }
            let _ = clip.wait();
        }
    }
}

pub(crate) fn run(name: &str, icon: &str, workdir: &str, argv: &[OsString]) -> bool {
    let _ = apps::appimage_install; // keep module linkage explicit
    if argv.is_empty() {
        return true;
    }
    if !workdir.is_empty() {
        let _ = env::set_current_dir(workdir);
    }

    let prog = maybe_heal_appimage(&argv[0]).unwrap_or_else(|| argv[0].clone());
    let started = Instant::now();

    let mut command = Command::new(&prog);
    if argv.len() > 1 {
        command.args(&argv[1..]);
    }
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());

    let (rc, err_text) = match command.spawn() {
        Ok(mut child) => {
            let captured = child
                .stderr
                .take()
                .map(|stderr| drain_capped(stderr, STDERR_CAP_BYTES))
                .unwrap_or_default();
            let rc = child.wait().ok().and_then(|s| s.code()).unwrap_or(128);
            let text = String::from_utf8_lossy(&captured)
                .trim_end_matches(&['\r', '\n'][..])
                .to_string();
            (rc, text)
        }
        Err(err) => {
            let rc = match err.kind() {
                ErrorKind::NotFound => 127,
                ErrorKind::PermissionDenied => 126,
                _ => 127,
            };
            (rc, format!("{}: {err}", prog.to_string_lossy()))
        }
    };

    if rc != 0 && started.elapsed() < Duration::from_secs(WINDOW_SECS) {
        notify_and_copy(name, icon, rc, &err_text);
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_last_three_non_blank_lines() {
        let body = "one\n\ntwo\n  \nthree\nfour\n\n";
        assert_eq!(tail_non_blank_lines(body, 3), "two\nthree\nfour");
    }

    #[test]
    fn drains_whole_stream_while_capping_buffer() {
        let payload = vec![b'x'; 100_000];
        let got = drain_capped(payload.as_slice(), 1024);
        assert_eq!(got.len(), 1024);
    }
}
