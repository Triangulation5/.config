use crate::hypr_ipc;
use serde_json::Value;
use std::{
    env, fs,
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

extern "C" {
    fn setsid() -> i32;
}

fn format_refresh_hz(hz: f64) -> String {
    let rounded = (hz * 1000.0).round() / 1000.0;
    if (rounded.fract()).abs() < 1e-9 {
        format!("{}", rounded as i64)
    } else {
        let s = format!("{rounded:.3}");
        s.trim_end_matches('0').trim_end_matches('.').to_string()
    }
}

fn format_number(val: f64) -> String {
    if (val.fract()).abs() < 1e-9 {
        format!("{}", val as i64)
    } else {
        let s = format!("{val:.4}");
        s.trim_end_matches('0').trim_end_matches('.').to_string()
    }
}

fn snapshot_monitor_spec(out: &str) -> Option<String> {
    let monitors = hypr_ipc::query_json("monitors")?.as_array()?.clone();
    let mon = monitors
        .into_iter()
        .find(|m| m.get("name").and_then(Value::as_str) == Some(out))?;
    let name = mon.get("name")?.as_str()?;
    let width = mon.get("width")?.as_i64()?;
    let height = mon.get("height")?.as_i64()?;
    let hz = mon
        .get("refreshRate")
        .and_then(Value::as_f64)
        .unwrap_or(60.0);
    let x = mon.get("x").and_then(Value::as_i64).unwrap_or(0);
    let y = mon.get("y").and_then(Value::as_i64).unwrap_or(0);
    let scale = mon.get("scale").and_then(Value::as_f64).unwrap_or(1.0);
    Some(format!(
        "hl.monitor({{ output = \"{name}\", mode = \"{width}x{height}@{}\", position = \"{x}x{y}\", scale = {} }}) return \"ok\"",
        format_refresh_hz(hz),
        format_number(scale)
    ))
}

fn spawn_rollback_timer(pending: &Path, old: &Path, token: &str) {
    let Ok(exe) = env::current_exe() else {
        return;
    };
    let mut cmd = Command::new(exe);
    cmd.arg("display-rollback-wait")
        .arg(pending)
        .arg(old)
        .arg(token)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // SAFETY: `setsid()` is async-signal-safe and detaches the 14s rollback timer
    // into its own session, matching `setsid -f` in `display-apply.sh`.
    unsafe {
        cmd.pre_exec(|| {
            let _ = setsid();
            Ok(())
        });
    }
    let _ = cmd.spawn();
}

pub(crate) fn rollback_wait(pending: &Path, old: &Path, token: &str) -> bool {
    thread::sleep(Duration::from_secs(14));
    if fs::read_to_string(pending)
        .map(|s| s.trim() == token)
        .unwrap_or(false)
    {
        if let Ok(old_spec) = fs::read_to_string(old) {
            let _ = hypr_ipc::eval(&old_spec);
        }
        let _ = fs::remove_file(pending);
        let _ = fs::remove_file(old);
    }
    true
}

pub(crate) fn run(
    verb: &str,
    out: &str,
    mode: Option<&str>,
    position: Option<&str>,
    scale: Option<&str>,
) -> bool {
    if out.is_empty() {
        return false;
    }
    let old_file = PathBuf::from(format!("/tmp/silhouette-display-{out}.old"));
    let pending_file = PathBuf::from(format!("/tmp/silhouette-display-{out}.pending"));

    match verb {
        "apply" => {
            let (Some(mode), Some(position), Some(scale)) = (mode, position, scale) else {
                return false;
            };
            if !old_file.exists() {
                let Some(spec) = snapshot_monitor_spec(out) else {
                    return false;
                };
                if fs::write(&old_file, spec).is_err() {
                    return false;
                }
            }
            let token = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos().to_string())
                .unwrap_or_else(|_| std::process::id().to_string());
            if fs::write(&pending_file, &token).is_err() {
                return false;
            }
            let new_spec = format!(
                "hl.monitor({{ output = \"{out}\", mode = \"{mode}\", position = \"{position}\", scale = {scale} }}) return \"ok\""
            );
            if !hypr_ipc::eval(&new_spec) {
                if let Ok(old_spec) = fs::read_to_string(&old_file) {
                    let _ = hypr_ipc::eval(&old_spec);
                }
                let _ = fs::remove_file(&pending_file);
                let _ = fs::remove_file(&old_file);
                return false;
            }
            spawn_rollback_timer(&pending_file, &old_file, &token);
            true
        }
        "keep" => {
            let _ = fs::remove_file(&pending_file);
            let _ = fs::remove_file(&old_file);
            true
        }
        "revert" => {
            if let Ok(old_spec) = fs::read_to_string(&old_file) {
                let _ = hypr_ipc::eval(&old_spec);
            }
            let _ = fs::remove_file(&pending_file);
            let _ = fs::remove_file(&old_file);
            true
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_hz_and_scale_like_jq() {
        assert_eq!(format_refresh_hz(60.0), "60");
        assert_eq!(format_refresh_hz(59.9999), "60");
        assert_eq!(format_refresh_hz(143.856), "143.856");
        assert_eq!(format_number(1.0), "1");
        assert_eq!(format_number(1.25), "1.25");
    }
}
