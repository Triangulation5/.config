use crate::config::{flags, is_image, resolve_dir, script_dir, state_dir};
use fs2::FileExt;
use rand::seq::SliceRandom;
use std::{
    fs,
    fs::OpenOptions,
    io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

fn list_pics(dir: &Path) -> Vec<PathBuf> {
    let mut pics = fs::read_dir(dir)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_file() && is_image(path))
        .collect::<Vec<_>>();
    pics.sort();
    pics
}

fn atomic_write(path: &Path, contents: &str) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension(format!(
        "{}.tmp",
        path.extension().and_then(|v| v.to_str()).unwrap_or("tmp")
    ));
    fs::write(&tmp, contents)?;
    fs::rename(tmp, path)
}

fn refill_bag(dir: &Path, bag: &Path, state: &Path) -> io::Result<()> {
    let mut pics = list_pics(dir);
    if pics.is_empty() {
        return Ok(());
    }
    let current = fs::read_to_string(state)
        .unwrap_or_default()
        .trim()
        .to_string();
    pics.shuffle(&mut rand::rng());
    if pics.len() > 1 && pics.first().is_some_and(|p| p.to_string_lossy() == current) {
        pics.rotate_left(1);
        pics.push(PathBuf::from(current));
    }
    if let Some(parent) = bag.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(
        bag,
        pics.iter()
            .map(|p| p.display().to_string())
            .collect::<Vec<_>>()
            .join("\n")
            + "\n",
    )
}

fn pop_bag(dir: &Path) -> Option<PathBuf> {
    let bag = state_dir().join("silhouette-wallpaper-bag");
    let state = state_dir().join("silhouette-wallpaper");
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(bag.with_extension("lock"))
        .ok()?;
    lock.lock_exclusive().ok()?;
    let mut refilled = false;
    loop {
        if fs::metadata(&bag).map(|m| m.len() == 0).unwrap_or(true) {
            if refilled {
                break;
            }
            refill_bag(dir, &bag, &state).ok()?;
            refilled = true;
            if fs::metadata(&bag).map(|m| m.len() == 0).unwrap_or(true) {
                break;
            }
        }
        let mut lines = fs::read_to_string(&bag)
            .ok()?
            .lines()
            .map(str::to_string)
            .collect::<Vec<_>>();
        if lines.is_empty() {
            break;
        }
        let candidate = PathBuf::from(lines.remove(0));
        fs::write(
            &bag,
            if lines.is_empty() {
                String::new()
            } else {
                lines.join("\n") + "\n"
            },
        )
        .ok()?;
        if candidate.is_file() {
            let _ = lock.unlock();
            return Some(candidate);
        }
    }
    let _ = lock.unlock();
    None
}

fn ensure_daemon() -> bool {
    if Command::new("awww")
        .arg("query")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
    {
        return true;
    }
    Command::new(script_dir().join("awww-daemon-wrapper.sh"))
        .arg("start")
        .status()
        .is_ok_and(|s| s.success())
}

pub(super) fn apply_wallpaper(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    if !ensure_daemon() {
        return false;
    }
    let roll: u8 = rand::random_range(0..100);
    let mut command = Command::new("awww");
    command.arg("img").arg(path);
    if roll < 55 {
        command.args([
            "--transition-type",
            "wave",
            "--transition-angle",
            "30",
            "--transition-wave",
            "60,30",
            "--transition-fps",
            "60",
            "--transition-step",
            "90",
        ]);
    } else if roll < 85 {
        command.args([
            "--transition-type",
            "grow",
            "--transition-pos",
            "top-right",
            "--transition-fps",
            "60",
            "--transition-step",
            "90",
        ]);
    } else if roll < 95 {
        command.args([
            "--transition-type",
            "wipe",
            "--transition-angle",
            "30",
            "--transition-fps",
            "60",
            "--transition-step",
            "90",
        ]);
    } else {
        command.args([
            "--transition-type",
            "fade",
            "--transition-fps",
            "60",
            "--transition-step",
            "90",
        ]);
    }
    let _ = command.status();
    if atomic_write(
        &state_dir().join("silhouette-wallpaper"),
        &format!("{}\n", path.display()),
    )
    .is_err()
    {
        return false;
    }

    let flags = flags();
    let palette = flags
        .get("paletteMode")
        .and_then(|v| v.as_str())
        .unwrap_or("static");
    let mut palette_command = Command::new("python3");
    palette_command
        .arg(script_dir().join("wallcolors.py"))
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if palette == "manual" {
        let hue = flags
            .get("manualHue")
            .and_then(|v| v.as_i64())
            .unwrap_or(30);
        let dark = flags
            .get("manualDark")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        palette_command.args([
            "--hue",
            &hue.to_string(),
            if dark { "dark" } else { "light" },
        ]);
    } else {
        palette_command.arg(path);
    }
    let _ = palette_command.status();
    let _ = Command::new("hyprctl")
        .arg("reload")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = Command::new("kitty")
        .args(["@", "load-config"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = Command::new("bash")
        .arg(script_dir().join("lock-wallpaper.sh"))
        .status();
    true
}

pub(super) fn resolve() -> bool {
    let dir = resolve_dir();
    atomic_write(
        &state_dir().join("silhouette-wallpaper-dir"),
        &format!("{}\n", dir.display()),
    )
    .is_ok()
}

pub(super) fn init() -> bool {
    let dir = resolve_dir();
    if let Ok(pic) = fs::read_to_string(state_dir().join("silhouette-wallpaper")) {
        let pic = pic.trim();
        if !pic.is_empty() && Path::new(pic).is_file() {
            return apply_wallpaper(Path::new(pic));
        }
    }
    pop_bag(&dir).is_some_and(|pic| apply_wallpaper(&pic))
}
