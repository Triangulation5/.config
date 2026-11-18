use super::{
    appimage::{appimage_install, install_for_launcher},
    desktop::{parse_desktop, write_entry},
    files::{copy_tree, is_elf, is_executable, make_executable, walk_files, TempDir},
    icons::install_icon,
    registry::{AppPaths, AppRecord},
    slug::{prettify, slugify},
};
use crate::{config::script_dir, config::state_dir};
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
        let status = Command::new("magick")
            .arg(source)
            .arg(&path)
            .status()
            .map_err(|error| format!("cannot start ImageMagick: {error}"))?;
        if !status.success() {
            return Err(format!("cannot convert wallpaper {}", source.display()));
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

fn command_exists(command: &str) -> bool {
    env::var_os("PATH").is_some_and(|paths| {
        env::split_paths(&paths).any(|directory| directory.join(command).is_file())
    })
}

#[derive(Clone, Copy)]
enum ArchiveKind {
    Generic,
    Deb,
}

fn extract_install(source: &Path, kind: ArchiveKind) -> Result<(), String> {
    let paths = AppPaths::new()?;
    let source_name = source
        .file_name()
        .ok_or_else(|| format!("invalid archive path: {}", source.display()))?
        .to_string_lossy();
    let stem = archive_stem(&source_name);
    let slug = slugify(&stem);

    let temp = TempDir::new("silhouette-app-archive")
        .map_err(|error| format!("cannot create extraction directory: {error}"))?;
    extract_archive(source, temp.path())?;
    if matches!(kind, ArchiveKind::Deb) {
        let data_archive = fs::read_dir(temp.path())
            .map_err(|error| format!("cannot inspect deb archive: {error}"))?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .find(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with("data.tar."))
            })
            .ok_or_else(|| format!("no data.tar in {source_name}"))?;
        let data = TempDir::new("silhouette-deb-data")
            .map_err(|error| format!("cannot create deb extraction directory: {error}"))?;
        extract_archive(&data_archive, data.path())?;
        return install_extracted_tree(&source_name, &stem, &slug, data.path(), &paths);
    }
    install_extracted_tree(&source_name, &stem, &slug, temp.path(), &paths)
}

fn install_extracted_tree(
    source_name: &str,
    stem: &str,
    slug: &str,
    tree: &Path,
    paths: &AppPaths,
) -> Result<(), String> {
    let entries = fs::read_dir(tree)
        .map_err(|error| format!("cannot inspect extracted archive: {error}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("cannot read extracted archive: {error}"))?;
    let tree = if entries.len() == 1 && entries[0].file_type().is_ok_and(|kind| kind.is_dir()) {
        entries[0].path()
    } else {
        tree.to_path_buf()
    };

    let files =
        walk_files(&tree).map_err(|error| format!("cannot scan {}: {error}", tree.display()))?;
    let desktop = files
        .iter()
        .find(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.ends_with(".desktop"))
                && (path.to_string_lossy().contains("usr/share/applications")
                    || path.to_string_lossy().contains("share/applications"))
        })
        .or_else(|| {
            files.iter().find(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "desktop")
            })
        });
    let info = desktop
        .and_then(|path| parse_desktop(path).ok())
        .unwrap_or_default();
    let binary = find_app_binary(&tree, &files, &info.exec)
        .ok_or_else(|| format!("no app inside {source_name}"))?;
    let name = if info.name.is_empty() {
        prettify(stem)
    } else {
        info.name
    };
    let app_id = if info.wmclass.is_empty() {
        name.clone()
    } else {
        info.wmclass.clone()
    };
    let mut registry = paths.read()?;
    let mut slug = slug.to_owned();
    let previous = registry.get(&slug).cloned().unwrap_or_default();
    let (action, obsolete_path) = if previous.appimage_path.is_empty() {
        ("new", None)
    } else if previous.app_id.is_empty() || previous.app_id == app_id {
        ("updated", Some(previous.appimage_path.clone()))
    } else {
        let mut suffix = 2;
        loop {
            let candidate = format!("{slug}-{suffix}");
            if !registry.contains_key(&candidate) {
                slug = candidate;
                break;
            }
            suffix += 1;
        }
        ("new", None)
    };

    let staging = TempDir::in_parent(&paths.apps_dir, "silhouette-app-stage")
        .map_err(|error| format!("cannot create installation staging directory: {error}"))?;
    let staged_app = staging.path().join("app");
    copy_tree(&tree, &staged_app)
        .map_err(|error| format!("cannot copy extracted app {}: {error}", source_name))?;
    let relative_binary = binary.strip_prefix(&tree).map_err(|_| {
        format!(
            "application binary escaped extraction tree: {}",
            binary.display()
        )
    })?;
    let destination = paths.apps_dir.join(&slug);
    replace_directory(&staged_app, &destination, staging.path())?;
    let binary_path = destination.join(relative_binary);
    make_executable(&binary_path)
        .map_err(|error| format!("cannot make {} executable: {error}", binary_path.display()))?;
    let _ = fs::remove_file(paths.icon_dir.join(format!("{slug}.png")));
    let _ = fs::remove_file(paths.icon_dir.join(format!("{slug}.svg")));
    install_icon(&destination, &info.icon, &paths.icon_dir, &slug)?;
    let icon_path = existing_icon(paths, &slug);
    let icon_value = icon_path
        .as_ref()
        .map(|path| path.to_string_lossy())
        .unwrap_or_default();
    let desktop_path = paths.desktop_dir.join(format!("silhouette-{slug}.desktop"));
    let legacy = paths.desktop_dir.join(format!("ricelin-{slug}.desktop"));
    let _ = fs::remove_file(legacy);
    write_entry(
        &desktop_path,
        &binary_path,
        &name,
        icon_value.as_ref(),
        &info.categories,
        &info.wmclass,
    )
    .map_err(|error| format!("cannot write {}: {error}", desktop_path.display()))?;
    registry.insert(
        slug,
        AppRecord {
            name: name.clone(),
            appimage_path: destination.to_string_lossy().into_owned(),
            icon_path: icon_path.unwrap_or_default().to_string_lossy().into_owned(),
            desktop_path: desktop_path.to_string_lossy().into_owned(),
            app_id,
        },
    );
    paths.write(&registry)?;
    if let Some(obsolete_path) = obsolete_path {
        if Path::new(&obsolete_path).canonicalize().ok() != destination.canonicalize().ok() {
            remove_previous_install(paths, &obsolete_path);
        }
    }
    println!("app\t{name}\t{action}");
    Ok(())
}

fn archive_stem(name: &str) -> String {
    let lower = name.to_ascii_lowercase();
    for suffix in [".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst"] {
        if lower.ends_with(suffix) {
            return name[..name.len() - suffix.len()].to_owned();
        }
    }
    for suffix in [".tgz", ".txz", ".tbz2", ".zip", ".deb", ".rpm"] {
        if lower.ends_with(suffix) {
            return name[..name.len() - suffix.len()].to_owned();
        }
    }
    name.to_owned()
}

fn extract_archive(source: &Path, destination: &Path) -> Result<(), String> {
    let program = if command_exists("bsdtar") {
        "bsdtar"
    } else if is_tar_archive(source) {
        "tar"
    } else {
        return Err(format!(
            "bsdtar is required to extract {}",
            source.display()
        ));
    };
    let status = Command::new(program)
        .arg("-xf")
        .arg(source)
        .arg("-C")
        .arg(destination)
        .stdin(Stdio::null())
        .status()
        .map_err(|error| format!("cannot start {program}: {error}"))?;
    if !status.success() {
        return Err(format!("cannot extract {}", source.display()));
    }
    Ok(())
}

fn is_tar_archive(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| {
            let name = name.to_ascii_lowercase();
            [
                ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".tar.zst",
            ]
            .iter()
            .any(|suffix| name.ends_with(suffix))
        })
}

fn find_app_binary(root: &Path, files: &[PathBuf], exec: &str) -> Option<PathBuf> {
    let executable = exec
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .trim_matches('"')
        .rsplit('/')
        .next()
        .unwrap_or_default();
    let mut named_script = None;
    if !executable.is_empty() {
        for path in files.iter().filter(|path| {
            path.file_name().and_then(|name| name.to_str()) == Some(executable)
                && is_executable(path)
        }) {
            if is_elf(path) {
                return Some(path.clone());
            }
            if named_script.is_none() && has_shebang(path) {
                named_script = Some(path.clone());
            }
        }
        if named_script.is_some() {
            return named_script;
        }
    }

    let mut largest = None;
    let mut largest_size = 0;
    let mut first_bin = None;
    for path in files
        .iter()
        .filter(|path| is_executable(path) && is_elf(path))
    {
        if path.components().any(|component| {
            matches!(
                component.as_os_str().to_str(),
                Some("lib" | "lib64" | "libexec")
            )
        }) {
            continue;
        }
        if first_bin.is_none()
            && path
                .components()
                .any(|component| component.as_os_str() == "bin")
        {
            first_bin = Some(path.clone());
        }
        let size = fs::metadata(path)
            .map(|metadata| metadata.len())
            .unwrap_or(0);
        if size > largest_size {
            largest_size = size;
            largest = Some(path.clone());
        }
    }
    first_bin.or(largest).filter(|path| path.starts_with(root))
}

fn has_shebang(path: &Path) -> bool {
    use std::io::Read;
    let Ok(mut file) = fs::File::open(path) else {
        return false;
    };
    let mut magic = [0; 2];
    file.read_exact(&mut magic).is_ok() && magic == *b"#!"
}

fn replace_directory(staged: &Path, destination: &Path, staging: &Path) -> Result<(), String> {
    let backup = staging.join("old");
    let had_destination = fs::symlink_metadata(destination).is_ok();
    if had_destination {
        fs::rename(destination, &backup)
            .map_err(|error| format!("cannot replace {}: {error}", destination.display()))?;
    }
    if let Err(error) = fs::rename(staged, destination) {
        if had_destination {
            let _ = fs::rename(&backup, destination);
        }
        return Err(format!("cannot install {}: {error}", destination.display()));
    }
    Ok(())
}

fn remove_previous_install(paths: &AppPaths, raw_path: &str) {
    if raw_path.is_empty() {
        return;
    }
    let path = Path::new(raw_path);
    if paths.owns_path(&paths.apps_dir, path) {
        if path.is_dir() {
            let _ = fs::remove_dir_all(path);
        } else {
            let _ = fs::remove_file(path);
        }
    }
}

fn existing_icon(paths: &AppPaths, slug: &str) -> Option<PathBuf> {
    ["png", "svg"]
        .into_iter()
        .map(|extension| paths.icon_dir.join(format!("{slug}.{extension}")))
        .find(|path| path.is_file())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn archive_names_drop_complete_suffixes() {
        assert_eq!(archive_stem("krita-5.2.tar.gz"), "krita-5.2");
        assert_eq!(archive_stem("tool.TAR.XZ"), "tool");
        assert_eq!(archive_stem("archive.zip"), "archive");
    }

    #[test]
    fn entrypoint_selection_prefers_matching_elf() {
        let temp = TempDir::new("silhouette-archive-test").unwrap();
        let root = temp.path();
        let files = vec![
            root.join("share/code"),
            root.join("usr/bin/code"),
            root.join("opt/app/bin/other"),
        ];
        for (path, bytes) in [
            (&files[0], b"#!/bin/sh\n".as_slice()),
            (&files[1], b"\x7fELF".as_slice()),
            (&files[2], b"\x7fELF".as_slice()),
        ] {
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, bytes).unwrap();
            make_executable(path).unwrap();
        }
        let selected = find_app_binary(root, &files, "code %U");
        assert_eq!(selected, Some(root.join("usr/bin/code")));
    }
}
