use crate::thumbs::json_escape;
use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Consolidated hotspot state reader (replaces sh+grep+nmcli + second nmcli).
/// Usage: hotspot-state <connection_name>
pub fn cmd_hotspot_state(args: &[String]) {
    let con = match args.first() {
        Some(c) if !c.is_empty() => c.as_str(),
        _ => std::process::exit(2),
    };

    let active = Command::new("nmcli")
        .args(["-t", "-f", "NAME", "connection", "show", "--active"])
        .output()
        .map(|o| {
            o.status.success()
                && String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .any(|line| line.trim() == con)
        })
        .unwrap_or(false);

    let mut name = String::new();
    let mut pw = String::new();
    if let Ok(o) = Command::new("nmcli")
        .args([
            "-t",
            "-s",
            "-g",
            "802-11-wireless.ssid,802-11-wireless-security.psk",
            "connection",
            "show",
            con,
        ])
        .output()
    {
        if o.status.success() {
            let txt = String::from_utf8_lossy(&o.stdout);
            let mut lines = txt.lines();
            if let Some(l1) = lines.next() {
                name = l1.to_string();
            }
            if let Some(l2) = lines.next() {
                pw = l2.to_string();
            }
        }
    }

    println!(
        "{{\"active\":{},\"name\":{},\"pw\":{}}}",
        if active { "true" } else { "false" },
        json_escape(&name),
        json_escape(&pw)
    );
}

/// Lists installed X cursor themes across standard icon directories (sorted, deduped).
pub fn cmd_cursor_themes() {
    let mut dirs: BTreeSet<PathBuf> = BTreeSet::new();
    if let Ok(home) = env::var("HOME") {
        if !home.is_empty() {
            let h = PathBuf::from(&home);
            dirs.insert(h.join(".icons"));
            dirs.insert(h.join(".local/share/icons"));
        }
    }
    dirs.insert(PathBuf::from("/usr/share/icons"));
    let xdg = env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".to_string());
    for part in xdg.split(':') {
        let trimmed = part.trim_end_matches('/');
        if !trimmed.is_empty() {
            dirs.insert(PathBuf::from(format!("{}/icons", trimmed)));
        }
    }

    let mut themes: BTreeSet<String> = BTreeSet::new();
    for d in dirs {
        let entries = match fs::read_dir(&d) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let p = entry.path();
            if p.join("cursors").is_dir() {
                if let Some(name) = entry.file_name().to_str() {
                    if !name.is_empty() {
                        themes.insert(name.to_string());
                    }
                }
            }
        }
    }

    let stdout = io::stdout();
    let mut out = stdout.lock();
    for t in themes {
        let _ = writeln!(out, "{}", t);
    }
    let _ = out.flush();
}

/// Decodes a cliphist entry by numeric id and copies it to the Wayland clipboard without `sh`.
pub fn cmd_clip_copy(args: &[String]) {
    let id = match args.first() {
        Some(s) if !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()) => s,
        _ => std::process::exit(2),
    };
    let dec = match Command::new("cliphist").args(["decode", id]).output() {
        Ok(o) if o.status.success() => o.stdout,
        _ => std::process::exit(1),
    };
    if let Ok(mut child) = Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(&dec);
        }
        let _ = child.wait();
    }
}

/// Deletes a cliphist entry by numeric id without `sh`.
pub fn cmd_clip_delete(args: &[String]) {
    let id = match args.first() {
        Some(s) if !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()) => s,
        _ => std::process::exit(2),
    };
    if let Ok(mut child) = Command::new("cliphist")
        .arg("delete")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(id.as_bytes());
        }
        let _ = child.wait();
    }
}

/// Atomically writes `<content>\n` to `<path>`, creating parent directories as needed.
pub fn cmd_write_file(args: &[String]) {
    if args.len() < 2 {
        std::process::exit(2);
    }
    let path = Path::new(&args[0]);
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    let content = format!("{}\n", args[1]);
    if fs::write(&tmp, content).is_ok() {
        let _ = fs::rename(&tmp, path);
    } else {
        let _ = fs::remove_file(&tmp);
        std::process::exit(1);
    }
}
