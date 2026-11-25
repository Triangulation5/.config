use crate::{config::home, hypr_ipc, proc_util::which_in_path};
use chrono::{Datelike, Local, Timelike};
use serde_json::Value;
use std::{
    collections::HashSet,
    fs,
    process::{Command, Stdio},
    thread,
    time::Duration,
};

const CLASS: &str = "note-inbox";
const MARGIN: i64 = 40;
const CANDIDATES: usize = 40;

fn format_stamps() -> (String, String, String) {
    let now = Local::now();
    let date = format!("{:04}-{:02}-{:02}", now.year(), now.month(), now.day());
    let (is_pm, hour12) = now.hour12();
    let ampm = if is_pm { "PM" } else { "AM" };
    let file_stamp = format!("{date} {hour12}-{:02} {ampm}", now.minute());
    let text_stamp = format!("{date} {hour12}:{:02} {ampm}", now.minute());
    (date, file_stamp, text_stamp)
}

fn client_addresses_for_class(clients: &Value) -> HashSet<String> {
    clients
        .as_array()
        .into_iter()
        .flatten()
        .filter(|c| c.get("class").and_then(Value::as_str) == Some(CLASS))
        .filter_map(|c| c.get("address").and_then(Value::as_str).map(str::to_string))
        .collect()
}

fn overlap_area(a: (i64, i64, i64, i64), b: (i64, i64, i64, i64)) -> i64 {
    let dx = (a.0 + a.2).min(b.0 + b.2) - a.0.max(b.0);
    let dy = (a.1 + a.3).min(b.1 + b.3) - a.1.max(b.1);
    if dx > 0 && dy > 0 {
        dx * dy
    } else {
        0
    }
}

fn pick_least_overlapping(
    mon_x: i64,
    mon_y: i64,
    mon_w: i64,
    mon_h: i64,
    win_w: i64,
    win_h: i64,
    others: &[(i64, i64, i64, i64)],
) -> (i64, i64) {
    let x_min = mon_x + MARGIN;
    let y_min = mon_y + MARGIN;
    let x_range = (mon_w - win_w - MARGIN * 2).max(0);
    let y_range = (mon_h - win_h - MARGIN * 2).max(0);

    let mut best = (x_min, y_min);
    let mut best_score = i64::MAX;

    for _ in 0..CANDIDATES {
        let cx = x_min + rand::random_range(0..=x_range);
        let cy = y_min + rand::random_range(0..=y_range);
        let score: i64 = others
            .iter()
            .map(|&other| overlap_area((cx, cy, win_w, win_h), other))
            .sum();
        if score < best_score {
            best_score = score;
            best = (cx, cy);
            if score == 0 {
                break;
            }
        }
    }
    best
}

pub(crate) fn run(stamped: bool) -> bool {
    for dep in ["kitty", "nvim"] {
        if which_in_path(dep).is_none() {
            eprintln!("missing dependency: {dep}");
            return false;
        }
    }

    let notes_dir = home().join("Documents/notes/inbox");
    if fs::create_dir_all(&notes_dir).is_err() {
        return false;
    }

    let (date, file_stamp, created) = format_stamps();
    let note_path = if stamped {
        notes_dir.join(format!("{file_stamp}.md"))
    } else {
        notes_dir.join(format!("{date}.md"))
    };

    let needs_init = fs::metadata(&note_path)
        .map(|m| m.len() == 0)
        .unwrap_or(true);
    if needs_init {
        let frontmatter = format!("---\ntitle: \ntags: [inbox]\ncreated: {created}\n---\n\n");
        if fs::write(&note_path, frontmatter).is_err() {
            return false;
        }
    }

    let Some(initial_clients) = hypr_ipc::query_json("clients") else {
        eprintln!("note-inbox: failed to query Hyprland clients");
        return false;
    };
    let before = client_addresses_for_class(&initial_clients);

    let spawned = Command::new("kitty")
        .args([
            "--class",
            CLASS,
            "--override",
            "initial_window_width=87c",
            "--override",
            "initial_window_height=26c",
            "nvim",
            "+2",
            "+startinsert!",
        ])
        .arg(&note_path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    if spawned.is_err() {
        return false;
    }

    let mut window_addr = String::new();
    for _ in 0..50 {
        if let Some(clients) = hypr_ipc::query_json("clients") {
            if let Some(found) = clients
                .as_array()
                .into_iter()
                .flatten()
                .filter(|c| c.get("class").and_then(Value::as_str) == Some(CLASS))
                .filter_map(|c| c.get("address").and_then(Value::as_str))
                .find(|addr| !before.contains(*addr))
            {
                window_addr = found.to_string();
                break;
            }
        }
        thread::sleep(Duration::from_millis(100));
    }
    if window_addr.is_empty() {
        return true;
    }

    let mut prev_size: Option<(i64, i64)> = None;
    let mut win_size = (0i64, 0i64);
    let mut mon_id: Option<i64> = None;
    for _ in 0..30 {
        if let Some(clients) = hypr_ipc::query_json("clients") {
            if let Some(win) =
                clients.as_array().into_iter().flatten().find(|c| {
                    c.get("address").and_then(Value::as_str) == Some(window_addr.as_str())
                })
            {
                let w = win.pointer("/size/0").and_then(Value::as_i64).unwrap_or(0);
                let h = win.pointer("/size/1").and_then(Value::as_i64).unwrap_or(0);
                mon_id = win.get("monitor").and_then(Value::as_i64);
                if w > 0 && h > 0 && prev_size == Some((w, h)) {
                    win_size = (w, h);
                    break;
                }
                prev_size = Some((w, h));
            }
        }
        thread::sleep(Duration::from_millis(50));
    }
    if win_size.0 <= 0 || win_size.1 <= 0 {
        return true;
    }
    let Some(mon_id) = mon_id else {
        return true;
    };

    let Some(monitors) = hypr_ipc::query_json("monitors") else {
        return true;
    };
    let Some(mon) = monitors
        .as_array()
        .into_iter()
        .flatten()
        .find(|m| m.get("id").and_then(Value::as_i64) == Some(mon_id))
    else {
        return true;
    };

    let raw_w = mon.get("width").and_then(Value::as_f64).unwrap_or(1920.0);
    let raw_h = mon.get("height").and_then(Value::as_f64).unwrap_or(1080.0);
    let transform = mon.get("transform").and_then(Value::as_i64).unwrap_or(0);
    let (dim_w, dim_h) = if transform % 2 == 1 {
        (raw_h, raw_w)
    } else {
        (raw_w, raw_h)
    };
    let scale = mon
        .get("scale")
        .and_then(Value::as_f64)
        .filter(|&s| s > 0.0)
        .unwrap_or(1.0);
    let w_logical = dim_w / scale;
    let h_logical = dim_h / scale;
    let mx = mon.get("x").and_then(Value::as_f64).unwrap_or(0.0);
    let my = mon.get("y").and_then(Value::as_f64).unwrap_or(0.0);
    let r0 = mon
        .pointer("/reserved/0")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let r1 = mon
        .pointer("/reserved/1")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let r2 = mon
        .pointer("/reserved/2")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let r3 = mon
        .pointer("/reserved/3")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);

    let mon_x = (mx + r0).floor() as i64;
    let mon_y = (my + r1).floor() as i64;
    let mon_w = (w_logical - r0 - r2).floor() as i64;
    let mon_h = (h_logical - r1 - r3).floor() as i64;
    let ws_id = mon
        .pointer("/activeWorkspace/id")
        .and_then(Value::as_i64)
        .unwrap_or(1);

    let others: Vec<(i64, i64, i64, i64)> = hypr_ipc::query_json("clients")
        .and_then(|v| v.as_array().cloned())
        .into_iter()
        .flatten()
        .filter(|c| {
            c.get("address").and_then(Value::as_str) != Some(window_addr.as_str())
                && c.get("mapped").and_then(Value::as_bool) == Some(true)
                && c.get("hidden").and_then(Value::as_bool) != Some(true)
                && c.pointer("/workspace/id").and_then(Value::as_i64) == Some(ws_id)
        })
        .map(|c| {
            (
                c.pointer("/at/0").and_then(Value::as_i64).unwrap_or(0),
                c.pointer("/at/1").and_then(Value::as_i64).unwrap_or(0),
                c.pointer("/size/0").and_then(Value::as_i64).unwrap_or(0),
                c.pointer("/size/1").and_then(Value::as_i64).unwrap_or(0),
            )
        })
        .collect();

    let (x, y) =
        pick_least_overlapping(mon_x, mon_y, mon_w, mon_h, win_size.0, win_size.1, &others);
    let _ = hypr_ipc::dispatch(&format!(
        "hl.dsp.window.move({{ x = {x}, y = {y}, window = 'address:{window_addr}' }})"
    ));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_non_overlapping_spot_when_available() {
        let others = vec![(40, 40, 800, 800)];
        let (x, y) = pick_least_overlapping(0, 0, 1920, 1080, 400, 300, &others);
        assert!(x >= 40 && y >= 40);
        assert_eq!(overlap_area((x, y, 400, 300), (40, 40, 800, 800)), 0);
    }
}
