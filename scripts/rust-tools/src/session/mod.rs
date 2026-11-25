mod awww;

pub(crate) use awww::awww_daemon;

use crate::{
    config::home,
    hypr_ipc,
    proc_util::{
        any_cmdline_matches, find_pids_by_name, stop_by_name, which_in_path, SIGKILL, SIGTERM,
    },
};
use std::{
    env,
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::Duration,
};

extern "C" {
    fn setsid() -> i32;
}

fn has_systemd() -> bool {
    Path::new("/run/systemd/system").is_dir() && which_in_path("systemctl").is_some()
}

fn systemd_user_check(subcmd: &str, unit: &str) -> bool {
    has_systemd()
        && Command::new("systemctl")
            .args(["--user", subcmd, "--quiet", unit])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
}

pub(super) fn spawn_detached(prog: &str, args: &[&str]) -> Option<u32> {
    let mut cmd = Command::new(prog);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // SAFETY: `setsid()` is async-signal-safe and detaches user daemons from the caller.
    unsafe {
        cmd.pre_exec(|| {
            let _ = setsid();
            Ok(())
        });
    }
    cmd.spawn().ok().map(|c| c.id())
}

pub(crate) fn user_service(cmd: &str, service: &str) -> bool {
    if !matches!(service, "hypridle" | "hyprsunset" | "mpd") {
        eprintln!("usage: user-service <start|stop|restart|status> <hypridle|hyprsunset|mpd>");
        return false;
    }

    let mpd_cfg = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
        .join("mpd/mpd.conf");
    let mpd_cfg_str = mpd_cfg.to_string_lossy().to_string();

    let spawn_service = || {
        if which_in_path(service).is_none() {
            return;
        }
        if service == "mpd" && mpd_cfg.is_file() {
            let _ = spawn_detached("mpd", &[mpd_cfg_str.as_str()]);
        } else {
            let _ = spawn_detached(service, &[]);
        }
    };

    match cmd {
        "start" => {
            if systemd_user_check("is-active", service) {
                return true;
            }
            if systemd_user_check("is-enabled", service)
                && Command::new("systemctl")
                    .args(["--user", "start", service])
                    .status()
                    .is_ok_and(|s| s.success())
            {
                return true;
            }
            if find_pids_by_name(service).is_empty() {
                spawn_service();
            }
            true
        }
        "restart" => {
            if (systemd_user_check("is-active", service)
                || systemd_user_check("is-enabled", service))
                && Command::new("systemctl")
                    .args(["--user", "restart", service])
                    .status()
                    .is_ok_and(|s| s.success())
            {
                return true;
            }
            let _ = stop_by_name(service, SIGTERM, 150);
            spawn_service();
            true
        }
        "stop" => {
            if has_systemd() {
                let _ = Command::new("systemctl")
                    .args(["--user", "stop", service])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
                if service == "mpd" {
                    let _ = Command::new("systemctl")
                        .args(["--user", "disable", "mpd"])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                }
            }
            let sig = if service == "mpd" { SIGKILL } else { SIGTERM };
            let _ = stop_by_name(service, sig, 150);
            true
        }
        "status" => {
            if systemd_user_check("is-active", service) {
                Command::new("systemctl")
                    .args(["--user", "status", service])
                    .status()
                    .is_ok_and(|s| s.success())
            } else if !find_pids_by_name(service).is_empty() {
                println!("{service} is running");
                true
            } else {
                println!("{service} is stopped");
                false
            }
        }
        _ => {
            eprintln!("usage: user-service <start|stop|restart|status> {service}");
            false
        }
    }
}

pub(crate) fn cliphist_watch() -> bool {
    if which_in_path("wl-paste").is_none() || which_in_path("cliphist").is_none() {
        return true;
    }
    for sel in ["text", "image"] {
        let expected = ["wl-paste", "--type", sel, "--watch", "cliphist", "store"];
        if !any_cmdline_matches(&expected) {
            let _ = spawn_detached("wl-paste", &["--type", sel, "--watch", "cliphist", "store"]);
        }
    }
    true
}

fn wait_for_proc(name: &str, max_ms: u64) -> bool {
    let mut waited = 0u64;
    while waited <= max_ms {
        if !find_pids_by_name(name).is_empty() {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
        waited += 50;
    }
    !find_pids_by_name(name).is_empty()
}

pub(crate) fn session_start() -> bool {
    if which_in_path("dbus-update-activation-environment").is_some() {
        let mut cmd = Command::new("dbus-update-activation-environment");
        if Path::new("/run/systemd/system").is_dir() {
            cmd.arg("--systemd");
        }
        let _ = cmd
            .args([
                "WAYLAND_DISPLAY",
                "XDG_CURRENT_DESKTOP",
                "HYPRLAND_INSTANCE_SIGNATURE",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }

    if !Path::new("/run/systemd/system").is_dir() && find_pids_by_name("pipewire").is_empty() {
        if which_in_path("gentoo-pipewire-launcher").is_some() {
            let _ = spawn_detached("gentoo-pipewire-launcher", &[]);
        } else if which_in_path("pipewire").is_some() {
            let _ = spawn_detached("pipewire", &[]);
            if which_in_path("wireplumber").is_some() {
                let _ = spawn_detached("wireplumber", &[]);
            }
            if which_in_path("pipewire-pulse").is_some() {
                let _ = spawn_detached("pipewire-pulse", &[]);
            }
        }
    }

    if !user_service("start", "hypridle") {
        hypr_ipc::notify_desktop(
            "Session start",
            "hypridle start command failed",
            "critical",
            None,
        );
    } else if !wait_for_proc("hypridle", 500) {
        hypr_ipc::notify_desktop(
            "Session start",
            "hypridle is not running after start (idle timeouts may not arm)",
            "critical",
            None,
        );
    }

    let sunset_conf = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
        .join("hypr/hyprsunset.conf");
    if sunset_conf.is_file() {
        if !user_service("start", "hyprsunset") {
            hypr_ipc::notify_desktop(
                "Session start",
                "hyprsunset start command failed",
                "critical",
                None,
            );
        } else if !wait_for_proc("hyprsunset", 500) {
            hypr_ipc::notify_desktop(
                "Session start",
                "hyprsunset is not running after start (night light disabled)",
                "critical",
                None,
            );
        }
    }

    true
}
