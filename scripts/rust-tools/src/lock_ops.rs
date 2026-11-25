use crate::{
    config::{flags, state_dir},
    hypr_ipc,
    proc_util::runtime_dir,
};
use image::{codecs::jpeg::JpegEncoder, imageops::FilterType};
use serde_json::Value;
use std::{
    fs::{self, OpenOptions},
    io::{BufWriter, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

const MAX_LOCK_DIM: u32 = 2560;
const JPEG_QUALITY: u8 = 92;

fn encode_mirror_native(src: &Path, dst: &Path) -> bool {
    let Ok(img) = image::open(src) else {
        return false;
    };
    let (w, h) = (img.width(), img.height());
    let resized = if w > MAX_LOCK_DIM || h > MAX_LOCK_DIM {
        img.resize(MAX_LOCK_DIM, MAX_LOCK_DIM, FilterType::Triangle)
    } else {
        img
    };
    let rgb = resized.to_rgb8();
    let Ok(file) = fs::File::create(dst) else {
        return false;
    };
    let mut writer = BufWriter::new(file);
    let mut enc = JpegEncoder::new_with_quality(&mut writer, JPEG_QUALITY);
    enc.encode_image(&rgb).is_ok() && writer.flush().is_ok()
}

fn encode_mirror_magick(src: &Path, dst: &Path) -> bool {
    Command::new("magick")
        .arg(src)
        .args(["-resize", "2560x2560>", "-quality", "92", "-strip"])
        .arg(dst)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

pub(crate) fn lock_wallpaper(pic_arg: Option<&Path>) -> bool {
    let state = state_dir();
    let _ = fs::create_dir_all(&state);
    let link = state.join("silhouette-lock-wallpaper");
    let mirror = state.join("silhouette-lock-wallpaper.jpg");

    let pic: PathBuf = match pic_arg.filter(|p| !p.as_os_str().is_empty()) {
        Some(p) => p.to_path_buf(),
        None => match fs::read_to_string(state.join("silhouette-wallpaper")) {
            Ok(raw) => PathBuf::from(raw.trim()),
            Err(_) => return true,
        },
    };
    if !pic.is_file() {
        return true;
    }

    let mirror_str = mirror.display().to_string();
    let pic_str = pic.display().to_string();
    if mirror.is_file() {
        if let Ok(existing) = fs::read_to_string(&link) {
            let mut lines = existing.lines();
            let mirrored = lines.next().unwrap_or("");
            let origin = lines.next().unwrap_or("");
            if mirrored == mirror_str && origin == pic_str {
                return true;
            }
        }
    }

    let pid = std::process::id();
    let tmp = state.join(format!("silhouette-lock-wallpaper.jpg.{pid}.jpg"));
    if !encode_mirror_native(&pic, &tmp) && !encode_mirror_magick(&pic, &tmp) {
        let _ = fs::remove_file(&tmp);
        return true;
    }
    if fs::rename(&tmp, &mirror).is_err() {
        let _ = fs::remove_file(&tmp);
        return true;
    }

    let link_tmp = state.join(format!("silhouette-lock-wallpaper.tmp.{pid}"));
    if fs::write(&link_tmp, format!("{mirror_str}\n{pic_str}\n")).is_ok() {
        let _ = fs::rename(&link_tmp, &link);
    }
    true
}

fn write_private_file(path: &Path, content: &str) -> bool {
    let Ok(mut file) = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
    else {
        return false;
    };
    file.write_all(content.as_bytes()).is_ok() && file.flush().is_ok()
}

pub(crate) fn lock_screen() -> bool {
    let runtime = runtime_dir();
    let trigger = runtime.join("silhouette-lock-trigger");
    let now_ns = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos().to_string())
        .unwrap_or_else(|_| "1".to_string());

    if flags().get("barEnabled").and_then(Value::as_bool) == Some(true) {
        if !write_private_file(&trigger, &format!("{now_ns}\n")) {
            hypr_ipc::notify_desktop(
                "Lock",
                &format!(
                    "Could not write {} — the lock did NOT engage",
                    trigger.display()
                ),
                "critical",
                None,
            );
            return false;
        }
        return true;
    }

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

    if monitors.is_empty() {
        hypr_ipc::notify_desktop(
            "Lock",
            "hyprctl reported no monitors; locking without a fresh grab",
            "critical",
            None,
        );
    }

    let mut children = Vec::with_capacity(monitors.len());
    for out in &monitors {
        let shot = runtime.join(format!("silhouette-lock-{out}.png"));
        let _ = fs::remove_file(&shot);
        let child = Command::new("grim")
            .args(["-o", out])
            .arg(&shot)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        children.push((out.clone(), shot, child));
    }

    for (out, shot, child) in children {
        let ok = match child {
            Ok(mut c) => {
                c.wait().is_ok_and(|s| s.success())
                    && fs::metadata(&shot).is_ok_and(|m| m.len() > 0)
            }
            Err(_) => false,
        };
        if !ok {
            hypr_ipc::notify_desktop(
                "Lock",
                &format!("grim failed to capture monitor {out}"),
                "critical",
                None,
            );
        }
    }

    if !write_private_file(&trigger, &format!("{now_ns}\n")) {
        hypr_ipc::notify_desktop(
            "Lock",
            &format!(
                "Could not write {} — the lock did NOT engage",
                trigger.display()
            ),
            "critical",
            None,
        );
        return false;
    }

    true
}
