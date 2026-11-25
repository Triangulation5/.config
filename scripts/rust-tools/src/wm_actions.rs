use crate::{
    config::{cache_dir, home, state_dir},
    hypr_ipc,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs,
    path::Path,
    process::{Command, Stdio},
};

fn exec_pill_on_active_monitor(target: &str) -> bool {
    let mut stack_buf = [0u8; 1024];
    if let Some(raw) = hypr_ipc::raw_request_stack(b"j/activeworkspace", &mut stack_buf) {
        if let Some(mon) = hypr_ipc::extract_json_str_fast(raw, b"\"monitor\"") {
            return hypr_ipc::exec_qs_ipc(&["pill", target, mon]);
        }
    }
    let mon = hypr_ipc::query_json("activeworkspace")
        .and_then(|v| v.get("monitor").and_then(Value::as_str).map(str::to_string))
        .unwrap_or_default();
    hypr_ipc::exec_qs_ipc(&["pill", target, &mon])
}

fn focused_workspace_id() -> i64 {
    hypr_ipc::query_json("monitors")
        .and_then(|v| v.as_array().cloned())
        .and_then(|arr| {
            arr.into_iter()
                .find(|m| m.get("focused").and_then(Value::as_bool) == Some(true))
                .and_then(|m| m.pointer("/activeWorkspace/id").and_then(Value::as_i64))
        })
        .unwrap_or(1)
}

fn active_window_addr_and_ws() -> Option<(String, String)> {
    let aw = hypr_ipc::query_json("activewindow")?;
    let addr = aw
        .get("address")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if addr.is_empty() {
        return None;
    }
    let ws = aw
        .pointer("/workspace/name")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    Some((addr, ws))
}

pub(crate) fn open_surface(surface: &str, arg: Option<&str>) -> bool {
    if surface == "dwmBar" {
        let action = arg.filter(|s| !s.is_empty()).unwrap_or("toggle");
        return hypr_ipc::exec_qs_ipc(&["bar", action]);
    }
    exec_pill_on_active_monitor(surface)
}

pub(crate) fn quick_record() -> bool {
    exec_pill_on_active_monitor("quickRecord")
}

pub(crate) fn minimize_toggle() -> bool {
    let Some((addr, ws)) = active_window_addr_and_ws() else {
        return true;
    };
    if ws == "special:minimized" {
        let real = focused_workspace_id();
        let payload = format!("{addr}|{real}");
        hypr_ipc::exec_qs_ipc(&["pill", "restoreWindow", &payload])
    } else {
        hypr_ipc::exec_qs_ipc(&["pill", "minimizeWindow", &addr])
    }
}

pub(crate) fn special_toggle(name: &str) -> bool {
    if name.is_empty() {
        return true;
    }
    let Some((addr, ws)) = active_window_addr_and_ws() else {
        return true;
    };
    let expr = if ws == format!("special:{name}") {
        let real = focused_workspace_id();
        format!("hl.dsp.window.move({{ workspace = {real}, window = \"address:{addr}\" }})")
    } else {
        format!(
            "hl.dsp.window.move({{ workspace = \"special:{name}\", follow = false, window = \"address:{addr}\" }})"
        )
    };
    hypr_ipc::dispatch(&expr)
}

#[derive(Serialize, Deserialize)]
struct GamemodeSnapshot {
    gaps_in: String,
    gaps_out: String,
    border_size: String,
    rounding: String,
    blur: String,
    shadow: String,
    anim: String,
}

fn val_int(opt: Option<&Value>, default: i64) -> String {
    opt.and_then(|v| v.get("int").and_then(Value::as_i64))
        .unwrap_or(default)
        .to_string()
}

fn val_bool(opt: Option<&Value>, default: bool) -> String {
    let val = opt
        .and_then(|v| {
            v.get("bool")
                .and_then(Value::as_bool)
                .or_else(|| v.get("int").and_then(Value::as_i64).map(|i| i != 0))
        })
        .unwrap_or(default);
    if val { "true" } else { "false" }.to_string()
}

fn val_gap(opt: Option<&Value>, default: i64) -> String {
    opt.and_then(|v| {
        v.get("css")
            .and_then(Value::as_str)
            .and_then(|s| s.split_whitespace().next())
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .or_else(|| v.get("int").and_then(Value::as_i64).map(|i| i.to_string()))
    })
    .unwrap_or_else(|| default.to_string())
}

fn write_atomic(path: &Path, body: &str) -> bool {
    if let Some(parent) = path.parent() {
        if fs::create_dir_all(parent).is_err() {
            return false;
        }
    }
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    if fs::write(&tmp, body).is_err() {
        return false;
    }
    fs::rename(&tmp, path).is_ok()
}

pub(crate) fn gamemode(mode: &str) -> bool {
    let snap_path = state_dir().join("silhouette/gamemode-snapshot.json");
    match mode {
        "on" => {
            if !snap_path.is_file() {
                let batch = hypr_ipc::get_options_batch([
                    "general:gaps_in",
                    "general:gaps_out",
                    "general:border_size",
                    "decoration:rounding",
                    "decoration:blur:enabled",
                    "decoration:shadow:enabled",
                    "animations:enabled",
                ]);
                let snap = GamemodeSnapshot {
                    gaps_in: val_gap(batch[0].as_ref(), 4),
                    gaps_out: val_gap(batch[1].as_ref(), 8),
                    border_size: val_int(batch[2].as_ref(), 1),
                    rounding: val_int(batch[3].as_ref(), 0),
                    blur: val_bool(batch[4].as_ref(), true),
                    shadow: val_bool(batch[5].as_ref(), true),
                    anim: val_bool(batch[6].as_ref(), true),
                };
                if let Ok(json) = serde_json::to_string(&snap) {
                    let _ = write_atomic(&snap_path, &(json + "\n"));
                }
            }
            hypr_ipc::eval(
                "hl.config({ general = { gaps_in = 0, gaps_out = 0, border_size = 0 }, decoration = { rounding = 0, blur = { enabled = false }, shadow = { enabled = false } }, animations = { enabled = false } })",
            )
        }
        "off" => {
            if let Ok(raw) = fs::read_to_string(&snap_path) {
                if let Ok(snap) = serde_json::from_str::<GamemodeSnapshot>(&raw) {
                    let expr = format!(
                        "hl.config({{ general = {{ gaps_in = {}, gaps_out = {}, border_size = {} }}, decoration = {{ rounding = {}, blur = {{ enabled = {} }}, shadow = {{ enabled = {} }} }}, animations = {{ enabled = {} }} }})",
                        snap.gaps_in,
                        snap.gaps_out,
                        snap.border_size,
                        snap.rounding,
                        snap.blur,
                        snap.shadow,
                        snap.anim
                    );
                    let ok = hypr_ipc::eval(&expr);
                    let _ = fs::remove_file(&snap_path);
                    return ok;
                }
            }
            hypr_ipc::reload()
        }
        _ => {
            eprintln!("usage: gamemode on|off");
            false
        }
    }
}

pub(crate) fn wake_display() -> bool {
    hypr_ipc::dispatch("dpms on")
}

pub(crate) fn kitty_opacity() -> bool {
    let style_path = home().join(".config/hypr/modules/style.lua");
    let body = fs::read_to_string(style_path).unwrap_or_default();
    let is_dwm = body.lines().any(|line| {
        let code = line.split("--").next().unwrap_or("");
        if let Some(idx) = code.find("dwmStyle") {
            let rest = code[idx + "dwmStyle".len()..].trim_start();
            if let Some(after_eq) = rest.strip_prefix('=') {
                return after_eq.trim_start().starts_with("true");
            }
        }
        false
    });
    let opacity = if is_dwm { "1.00" } else { "0.94" };
    let out = cache_dir().join("silhouette/kitty-opacity");
    if !write_atomic(&out, &format!("background_opacity {opacity}\n")) {
        return false;
    }
    let _ = Command::new("kitty")
        .args(["@", "load-config"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = Command::new("kitty")
        .args(["@", "set-background-opacity", opacity])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    true
}
