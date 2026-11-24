use super::{
    archive::command_exists,
    desktop::{parse_desktop, write_entry},
    files::{copy_tree, is_elf, is_executable, make_executable, walk_files, TempDir},
    icons::install_icon,
    registry::{AppPaths, AppRecord},
    slug::{prettify, slugify},
};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

#[derive(Clone, Copy)]
pub(super) enum ArchiveKind {
    Generic,
    Deb,
}

pub(super) fn extract_install(source: &Path, kind: ArchiveKind) -> Result<(), String> {
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
