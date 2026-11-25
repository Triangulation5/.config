use crate::{
    config::state_dir,
    hypr_ipc,
    proc_util::{find_pids_by_name, pid_alive, runtime_dir, stop_by_name, which_in_path, SIGTERM},
};
use std::{
    env,
    fs::{self, OpenOptions},
    os::unix::{fs::FileTypeExt, process::CommandExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::Duration,
};

extern "C" {
    fn setsid() -> i32;
}

fn awww_socket_paths() -> Vec<PathBuf> {
    let rt = runtime_dir();
    let mut paths = Vec::new();
    if let Ok(wd) = env::var("WAYLAND_DISPLAY") {
        if !wd.is_empty() {
            paths.push(rt.join(format!("{wd}-awww-daemon.sock")));
        }
    }
    let default_sock = rt.join("wayland-1-awww-daemon.sock");
    if !paths.contains(&default_sock) {
        paths.push(default_sock);
    }
    paths
}

fn is_unix_socket(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_socket())
}

fn awww_socket_ok() -> bool {
    awww_socket_paths().iter().any(|p| is_unix_socket(p))
        && Command::new("awww")
            .arg("query")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
}

fn cleanup_awww_sockets() {
    for sock in awww_socket_paths() {
        if sock.exists() || fs::symlink_metadata(&sock).is_ok() {
            let _ = fs::remove_file(&sock);
        }
    }
}

pub(crate) fn awww_daemon(action: &str) -> bool {
    let daemon_cmd = env::var("DAEMON_CMD").unwrap_or_else(|_| "awww-daemon".to_string());
    let daemon_base = daemon_cmd
        .rsplit('/')
        .next()
        .unwrap_or("awww-daemon")
        .to_string();
    let state = state_dir();
    let pid_file = state.join("awww-daemon-wrapper.pid");
    let log_file = state.join("awww-daemon-wrapper.log");

    let stop = || -> bool {
        let pids = find_pids_by_name(&daemon_base);
        if pids.is_empty() {
            cleanup_awww_sockets();
            let _ = fs::remove_file(&pid_file);
            return true;
        }
        if stop_by_name(&daemon_base, SIGTERM, 2000) {
            cleanup_awww_sockets();
            let _ = fs::remove_file(&pid_file);
            true
        } else {
            hypr_ipc::notify_desktop(
                "awww-daemon",
                "Daemon did not stop on SIGTERM; not killing forcefully",
                "critical",
                None,
            );
            false
        }
    };

    let start = || -> bool {
        if awww_socket_ok() {
            return true;
        }
        if which_in_path(&daemon_cmd).is_none() {
            return false;
        }
        let _ = fs::create_dir_all(&state);
        cleanup_awww_sockets();
        let Ok(log_out) = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&log_file)
        else {
            return false;
        };
        let Ok(log_err) = log_out.try_clone() else {
            return false;
        };

        let mut cmd = Command::new(&daemon_cmd);
        cmd.stdin(Stdio::null()).stdout(log_out).stderr(log_err);
        // SAFETY: `setsid()` detaches `awww-daemon` into its own session.
        unsafe {
            cmd.pre_exec(|| {
                let _ = setsid();
                Ok(())
            });
        }
        let Ok(child) = cmd.spawn() else {
            hypr_ipc::notify_desktop("awww-daemon", "Failed to spawn daemon", "critical", None);
            return false;
        };
        let pid = child.id();
        for _ in 0..25 {
            if awww_socket_ok() {
                let _ = fs::write(&pid_file, format!("{pid}\n"));
                return true;
            }
            if !pid_alive(pid) {
                hypr_ipc::notify_desktop(
                    "awww-daemon",
                    &format!("Daemon exited during startup; see {}", log_file.display()),
                    "critical",
                    None,
                );
                return false;
            }
            thread::sleep(Duration::from_millis(200));
        }
        hypr_ipc::notify_desktop(
            "awww-daemon",
            &format!(
                "Daemon did not create its socket within ~5s; see {}",
                log_file.display()
            ),
            "critical",
            None,
        );
        false
    };

    match action {
        "start" => start(),
        "stop" => stop(),
        "restart" => {
            let _ = stop();
            start()
        }
        "status" => {
            let pids = find_pids_by_name(&daemon_base);
            if !pids.is_empty() && awww_socket_ok() {
                let list = pids
                    .iter()
                    .map(u32::to_string)
                    .collect::<Vec<_>>()
                    .join(" ");
                println!("awww-daemon: running (pids: {list}), socket OK");
                true
            } else if !pids.is_empty() {
                println!("awww-daemon: running but socket is unusable — try 'restart'");
                hypr_ipc::notify_desktop(
                    "awww-daemon",
                    "Daemon is running but its socket is unusable",
                    "normal",
                    None,
                );
                false
            } else {
                println!("awww-daemon: not running");
                false
            }
        }
        _ => {
            eprintln!("usage: awww-daemon {{status|start|restart|stop}}");
            false
        }
    }
}
