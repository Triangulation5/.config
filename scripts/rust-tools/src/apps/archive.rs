use super::{
    appimage::{appimage_install, install_for_launcher},
    extract::{extract_install, ArchiveKind},
    slug::prettify,
};
use crate::{config::script_dir, config::state_dir, wallpaper};
use serde_json::Value;
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

pub(super) fn app_install(operation: &str, args: &[std::ffi::OsString]) -> Result<(), String> {
    match operation {
        "install" => {
            let source = args
                .first()
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
                .ok_or_else(|| "usage: app-install.sh install <file>".to_owned())?;
            install(&source)
        }
        "remove" | "rename" => appimage_install(operation, args),
        _ => Err("usage: app-install.sh install|remove|rename ...".to_owned()),
    }
}

fn install(source: &Path) -> Result<(), String> {
    if !source.is_file() {
        return Err(format!("no such file: {}", source.display()));
    }
    let filename = source
        .file_name()
        .ok_or_else(|| format!("invalid file path: {}", source.display()))?;
    let base = filename.to_string_lossy();
    let lowercase = base.to_ascii_lowercase();

    if lowercase.ends_with(".appimage") {
        return install_for_launcher(source);
    }
    if [".pkg.tar.zst", ".pkg.tar.xz", ".pkg.tar.gz", ".pkg.tar.bz2"]
        .iter()
        .any(|suffix| lowercase.ends_with(suffix))
    {
        return install_native(
            "pacman",
            ["-U", "--noconfirm"],
            source,
            "native",
            &prettify(&base),
        );
    }
    if lowercase.ends_with(".deb") {
        if command_exists("apt-get") {
            return install_native(
                "apt-get",
                ["install", "-y"],
                source,
                "native",
                &prettify(&base),
            );
        }
        return extract_install(source, ArchiveKind::Deb);
    }
    if lowercase.ends_with(".rpm") {
        if command_exists("dnf") {
            return install_native("dnf", ["install", "-y"], source, "native", &prettify(&base));
        }
        if command_exists("zypper") {
            return install_native(
                "zypper",
                ["--non-interactive", "install", "--allow-unsigned-rpm"],
                source,
                "native",
                &prettify(&base),
            );
        }
        return extract_install(source, ArchiveKind::Generic);
    }
    if lowercase.ends_with(".flatpakref") {
        let status = Command::new("flatpak")
            .args(["install", "--user", "-y", "--noninteractive"])
            .arg(source)
            .status()
            .map_err(|error| format!("cannot start flatpak: {error}"))?;
        if !status.success() {
            return Err(format!("flatpak install failed: {}", source.display()));
        }
        println!("native\t{}\tnew", prettify(&base));
        return Ok(());
    }
    if [
        ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".tar.zst", ".zip",
    ]
    .iter()
    .any(|suffix| lowercase.ends_with(suffix))
    {
        return extract_install(source, ArchiveKind::Generic);
    }
    if lowercase.ends_with(".ttf") || lowercase.ends_with(".otf") {
        return install_font(source, &base);
    }
    if [".png", ".jpg", ".jpeg", ".webp"]
        .iter()
        .any(|suffix| lowercase.ends_with(suffix))
    {
        return install_wallpaper(source, &base);
    }
    Err(format!("unsupported: {base}"))
}

fn install_native<const N: usize>(
    program: &str,
    arguments: [&str; N],
    source: &Path,
    kind: &str,
    name: &str,
) -> Result<(), String> {
    if !command_exists(program) {
        return Err(format!("{program} is not installed"));
    }
    let status = Command::new("pkexec")
        .arg(program)
        .args(arguments)
        .arg(source)
        .status()
        .map_err(|error| format!("cannot start pkexec: {error}"))?;
    if !status.success() {
        return Err(format!(
            "{program} installation failed for {}",
            source.display()
        ));
    }
    println!("{kind}\t{name}\tnew");
    Ok(())
}

fn install_font(source: &Path, base: &str) -> Result<(), String> {
    let data_home = env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))
        .ok_or_else(|| "HOME is not set".to_owned())?;
    let font_dir = data_home.join("fonts");
    fs::create_dir_all(&font_dir)
        .map_err(|error| format!("cannot create {}: {error}", font_dir.display()))?;
    let destination = font_dir.join(base);
    let action = if destination.is_file() {
        "updated"
    } else {
        "new"
    };
    fs::copy(source, &destination).map_err(|error| {
        format!(
            "cannot copy font {} to {}: {error}",
            source.display(),
            destination.display()
        )
    })?;
    let _ = Command::new("fc-cache")
        .args(["-f"])
        .arg(&font_dir)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    println!(
        "font\t{}\t{action}\t{}",
        Path::new(base)
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy(),
        destination.display()
    );
    Ok(())
}

fn install_wallpaper(source: &Path, base: &str) -> Result<(), String> {
    let flags_path = state_dir().join("silhouette/flags.json");
    let flags = fs::read_to_string(flags_path)
        .ok()
        .and_then(|body| serde_json::from_str::<Value>(&body).ok())
        .unwrap_or(Value::Null);
    let mut wallpaper_dir = flags
        .get("wallpaperDir")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(expand_tilde);
    if wallpaper_dir.is_none() {
        wallpaper_dir = fs::read_to_string(state_dir().join("silhouette-wallpaper-dir"))
            .ok()
            .map(|value| expand_tilde(value.trim()))
            .filter(|value| !value.as_os_str().is_empty());
    }
    let wallpaper_dir = wallpaper_dir.unwrap_or_else(|| {
        env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default()
            .join("Pictures")
    });
    fs::create_dir_all(&wallpaper_dir)
        .map_err(|error| format!("cannot create {}: {error}", wallpaper_dir.display()))?;
    let stem = Path::new(base)
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy();
    let destination = if base.to_ascii_lowercase().ends_with(".webp") {
        let path = wallpaper_dir.join(format!("{stem}.png"));
        let converted_in_proc = image::open(source)
            .ok()
            .is_some_and(|img| img.save(&path).is_ok());
        if !converted_in_proc {
            let status = Command::new("magick")
                .arg(source)
                .arg(&path)
                .status()
                .map_err(|error| format!("cannot start ImageMagick: {error}"))?;
            if !status.success() {
                return Err(format!("cannot convert wallpaper {}", source.display()));
            }
        }
        path
    } else {
        let path = wallpaper_dir.join(base);
        fs::copy(source, &path).map_err(|error| {
            format!(
                "cannot copy wallpaper {} to {}: {error}",
                source.display(),
                path.display()
            )
        })?;
        path
    };
    if !wallpaper::apply_wallpaper(&destination) {
        let script = script_dir().join("wallpaper.sh");
        let status = Command::new("bash")
            .arg(script)
            .args(["set"])
            .arg(&destination)
            .status()
            .map_err(|error| format!("cannot start wallpaper script: {error}"))?;
        if !status.success() {
            return Err(format!(
                "wallpaper script could not set {}",
                destination.display()
            ));
        }
    }
    println!("wallpaper\t{}\tset", stem);
    Ok(())
}

fn expand_tilde(value: &str) -> PathBuf {
    if value == "~" {
        env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
    } else if let Some(value) = value.strip_prefix("~/") {
        env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default()
            .join(value)
    } else {
        PathBuf::from(value)
    }
}

pub(super) fn command_exists(command: &str) -> bool {
    env::var_os("PATH").is_some_and(|paths| {
        env::split_paths(&paths).any(|directory| directory.join(command).is_file())
    })
}
