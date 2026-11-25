use crate::{
    config::{cache_dir, flags, home, state_dir},
    hypr_ipc, lock_ops,
    proc_util::{runtime_dir, which_in_path},
};
use serde_json::Value;
use std::{
    env,
    ffi::OsString,
    fs::{self, OpenOptions},
    io::Write,
    os::{
        fd::{IntoRawFd, OwnedFd},
        unix::{fs::OpenOptionsExt, process::CommandExt},
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::Duration,
};
use zbus::{connection::Builder, zvariant::OwnedFd as ZbusOwnedFd};

const F_SETFD: i32 = 2;

extern "C" {
    fn fcntl(fd: i32, cmd: i32, arg: i32) -> i32;
}

/// Acquire a logind idle+sleep inhibitor lock FD directly over the system D-Bus
/// and clear `FD_CLOEXEC` so the `exec`d child (`sleep infinity`) inherits the
/// lock directly with zero extra wrapper processes resident in memory.
fn acquire_logind_inhibit_fd(who: &str, why: &str) -> Option<i32> {
    zbus::block_on(async move {
        let conn = Builder::system().ok()?.build().await.ok()?;
        let reply = conn
            .call_method(
                Some("org.freedesktop.login1"),
                "/org/freedesktop/login1",
                Some("org.freedesktop.login1.Manager"),
                "Inhibit",
                &("idle:sleep", who, why, "block"),
            )
            .await
            .ok()?;
        let zfd: ZbusOwnedFd = reply.body().deserialize().ok()?;
        let std_fd: OwnedFd = zfd.into();
        let raw = std_fd.into_raw_fd();
        // SAFETY: clearing `FD_CLOEXEC` (flag 0) on a valid owned FD lets the
        // `exec`d target hold the logind pipe open for its lifetime.
        let rc = unsafe { fcntl(raw, F_SETFD, 0) };
        if rc < 0 {
            return None;
        }
        Some(raw)
    })
}

pub(crate) fn inhibit(argv: &[OsString]) -> bool {
    if argv.is_empty() {
        eprintln!("usage: inhibit <command> [args...]");
        return false;
    }
    let who = env::var("USER").unwrap_or_else(|_| "silhouette".to_string());
    let why = env::var("INHIBIT_WHY").unwrap_or_else(|_| "keep awake".to_string());

    if acquire_logind_inhibit_fd(&who, &why).is_some() {
        let err = Command::new(&argv[0]).args(&argv[1..]).exec();
        eprintln!("inhibit: failed to exec {:?}: {err}", argv[0]);
        return false;
    }

    let what_arg = "--what=idle:sleep";
    let who_arg = format!("--who={who}");
    let why_arg = format!("--why={why}");
    let mode_arg = "--mode=block";

    for tool in ["systemd-inhibit", "elogind-inhibit"] {
        if tool == "systemd-inhibit"
            && !Path::new("/run/systemd/system").is_dir()
            && which_in_path("elogind-inhibit").is_some()
        {
            continue;
        }
        if which_in_path(tool).is_some() {
            let err = Command::new(tool)
                .args([what_arg, &who_arg, &why_arg, mode_arg])
                .args(argv)
                .exec();
            eprintln!("inhibit: failed to exec {tool}: {err}");
            return false;
        }
    }

    let err = Command::new(&argv[0]).args(&argv[1..]).exec();
    eprintln!("inhibit: failed to exec {:?}: {err}", argv[0]);
    false
}

fn is_systemd() -> bool {
    Path::new("/run/systemd/system").is_dir() && which_in_path("systemctl").is_some()
}

fn has_elogind() -> bool {
    !Path::new("/run/systemd/system").is_dir()
        && which_in_path("loginctl").is_some()
        && Command::new("loginctl")
            .args(["list-sessions", "--no-legend"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
}

fn capture_pre_suspend_wake_frames() {
    let wake_enabled = flags()
        .get("wakeAnimation")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    if !wake_enabled {
        return;
    }

    let rt = runtime_dir();
    let monitors: Vec<String> = hypr_ipc::query_json("monitors")
        .and_then(|v| v.as_array().cloned())
        .map(|arr| {
            arr.into_iter()
                .filter_map(|m| {
                    m.get("name")
                        .and_then(Value::as_str)
                        .filter(|s| !s.is_empty())
                        .map(str::to_string)
                })
                .collect()
        })
        .unwrap_or_default();

    let mut children = Vec::with_capacity(monitors.len());
    for out in &monitors {
        let dst = rt.join(format!("silhouette-wake-{out}.png"));
        let _ = fs::remove_file(&dst);
        if let Ok(child) = Command::new("grim")
            .args(["-o", out])
            .arg(&dst)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            children.push(child);
        }
    }
    for mut child in children {
        let _ = child.wait();
    }

    if let Ok(mut marker) = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .mode(0o600)
        .open(rt.join("silhouette-wake-active"))
    {
        let _ = marker.write_all(b"1\n");
    }

    thread::sleep(Duration::from_millis(150));
}

pub(crate) fn power(action: &str) -> bool {
    match action {
        "suspend" => {
            capture_pre_suspend_wake_frames();
            if is_systemd() {
                let _ = Command::new("systemctl").arg("suspend").exec();
            } else if has_elogind() {
                let _ = Command::new("loginctl").arg("suspend").exec();
            } else if which_in_path("zzz").is_some() {
                let _ = Command::new("zzz").exec();
            } else if which_in_path("doas").is_some()
                && Command::new("doas")
                    .args(["-n", "true"])
                    .stderr(Stdio::null())
                    .status()
                    .is_ok_and(|s| s.success())
            {
                let _ = Command::new("doas")
                    .args(["sh", "-c", "echo mem > /sys/power/state"])
                    .exec();
            } else if which_in_path("sudo").is_some()
                && Command::new("sudo")
                    .args(["-n", "true"])
                    .stderr(Stdio::null())
                    .status()
                    .is_ok_and(|s| s.success())
            {
                let _ = Command::new("sudo")
                    .args(["sh", "-c", "echo mem > /sys/power/state"])
                    .exec();
            } else if fs::write("/sys/power/state", "mem\n").is_ok() {
                return true;
            }
            eprintln!("power: no supported suspend mechanism found");
            false
        }
        "reboot" => {
            if is_systemd() {
                let _ = Command::new("systemctl").arg("reboot").exec();
            } else if has_elogind() {
                let _ = Command::new("loginctl").arg("reboot").exec();
            } else if which_in_path("openrc-shutdown").is_some() {
                let _ = Command::new("openrc-shutdown").args(["-r", "now"]).exec();
            } else {
                let _ = Command::new("reboot").exec();
            }
            false
        }
        "shutdown" | "poweroff" => {
            if is_systemd() {
                let _ = Command::new("systemctl").arg("poweroff").exec();
            } else if has_elogind() {
                let _ = Command::new("loginctl").arg("poweroff").exec();
            } else if which_in_path("openrc-shutdown").is_some() {
                let _ = Command::new("openrc-shutdown").args(["-p", "now"]).exec();
            } else {
                let _ = Command::new("poweroff").exec();
            }
            false
        }
        "lock" => lock_ops::lock_screen(),
        _ => {
            eprintln!("usage: power <suspend|reboot|shutdown|poweroff|lock>");
            false
        }
    }
}

fn move_one(old: &Path, new: &Path) {
    if !old.exists() {
        return;
    }
    if new.exists() {
        eprintln!(
            "migrate-state: {} and {} both exist, left the old one alone",
            old.display(),
            new.display()
        );
        return;
    }
    if let Some(parent) = new.parent() {
        if fs::create_dir_all(parent).is_err() {
            return;
        }
    }
    if fs::rename(old, new).is_ok() {
        println!(
            "migrate-state: moved {} to {}",
            old.display(),
            new.display()
        );
    } else {
        eprintln!(
            "migrate-state: could not move {}, continuing without it",
            old.display()
        );
    }
}

fn reword_file(old: &str, new: &str, file: &Path) {
    let Ok(body) = fs::read_to_string(file) else {
        return;
    };
    if !body.contains(old) {
        return;
    }
    let updated = body.replace(old, new);
    if fs::write(file, updated).is_ok() {
        println!("migrate-state: reworded {old} in {}", file.display());
    }
}

pub(crate) fn migrate_state() -> bool {
    let state = state_dir();
    let cache = cache_dir();
    let data = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share"));

    move_one(&state.join("ricelin"), &state.join("silhouette"));
    move_one(
        &state.join("ricelin-wallpaper"),
        &state.join("silhouette-wallpaper"),
    );
    move_one(
        &state.join("ricelin-wallpaper-dir"),
        &state.join("silhouette-wallpaper-dir"),
    );
    move_one(
        &state.join("ricelin-wallpaper-bag"),
        &state.join("silhouette-wallpaper-bag"),
    );
    move_one(
        &state.join("ricelin-wallpaper-bag.lock"),
        &state.join("silhouette-wallpaper-bag.lock"),
    );

    move_one(&cache.join("ricelin"), &cache.join("silhouette"));
    move_one(
        &cache.join("ricelin-wp-thumbs"),
        &cache.join("silhouette-wp-thumbs"),
    );

    let data_old = data.join("ricelin");
    let data_new = data.join("silhouette");
    move_one(&data_old, &data_new);

    let old_s = data_old.to_string_lossy().to_string();
    let new_s = data_new.to_string_lossy().to_string();
    reword_file(&old_s, &new_s, &data_new.join("appimages.json"));
    if let Ok(entries) = fs::read_dir(data.join("applications")) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.extension().and_then(|e| e.to_str()) == Some("desktop") {
                reword_file(&old_s, &new_s, &p);
            }
        }
    }

    let home_dir = home();
    let home_old = home_dir.join("Ricelin/wallpapers");
    let home_new = home_dir.join("Silhouette/wallpapers");
    move_one(&home_old, &home_new);

    let hold_s = home_old.to_string_lossy().to_string();
    let hnew_s = home_new.to_string_lossy().to_string();
    reword_file(&hold_s, &hnew_s, &state.join("silhouette/flags.json"));
    reword_file(&hold_s, &hnew_s, &state.join("silhouette-wallpaper"));
    reword_file(&hold_s, &hnew_s, &state.join("silhouette-wallpaper-dir"));
    reword_file(&hold_s, &hnew_s, &state.join("silhouette-wallpaper-bag"));

    if home_new.is_dir() {
        let _ = fs::remove_dir(home_dir.join("Ricelin"));
    }
    true
}
