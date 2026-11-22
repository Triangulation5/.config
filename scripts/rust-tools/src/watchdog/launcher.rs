use super::probe::full_ipc_probe;
use std::{
    path::Path,
    process::{Command, Stdio},
    thread,
    time::Duration,
};

/// Relaunch the shell through `launch.sh -d` and wait until IPC answers or the
/// spawned launch process exits (capped at `poll_ticks * step`).
pub(crate) fn launch_shell(name: &str, scripts_dir: &Path, step: Duration, poll_ticks: u32) {
    let launch_script = scripts_dir.join("launch.sh");
    let Ok(mut child) = Command::new("bash")
        .arg(&launch_script)
        .arg("-d")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return;
    };

    for _ in 0..poll_ticks {
        if full_ipc_probe(name) {
            return;
        }
        match child.try_wait() {
            Ok(Some(_)) | Err(_) => return,
            Ok(None) => {}
        }
        thread::sleep(step);
    }
}
