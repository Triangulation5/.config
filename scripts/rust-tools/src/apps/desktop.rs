use std::{
    collections::VecDeque,
    fs, io,
    path::{Path, PathBuf},
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
};

static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Default)]
pub(super) struct DesktopInfo {
    pub(super) name: String,
    pub(super) icon: String,
    pub(super) categories: String,
    pub(super) wmclass: String,
    pub(super) exec: String,
}

pub(super) fn parse_desktop(path: &Path) -> io::Result<DesktopInfo> {
    let body = fs::read_to_string(path)?;
    let mut info = DesktopInfo::default();
    for line in body.lines() {
        if info.name.is_empty() {
            info.name = line
                .strip_prefix("Name=")
                .map(str::to_owned)
                .unwrap_or_default();
        }
        if info.icon.is_empty() {
            info.icon = line
                .strip_prefix("Icon=")
                .map(str::to_owned)
                .unwrap_or_default();
        }
        if info.categories.is_empty() {
            info.categories = line
                .strip_prefix("Categories=")
                .map(str::to_owned)
                .unwrap_or_default();
        }
        if info.wmclass.is_empty() {
            info.wmclass = line
                .strip_prefix("StartupWMClass=")
                .map(str::to_owned)
                .unwrap_or_default();
        }
        if info.exec.is_empty() {
            info.exec = line
                .strip_prefix("Exec=")
                .map(str::to_owned)
                .unwrap_or_default();
        }
    }
    Ok(info)
}

pub(super) fn find_desktop_file(root: &Path, max_depth: usize) -> io::Result<Option<PathBuf>> {
    let mut candidates = Vec::new();
    let mut directories = VecDeque::from([(root.to_path_buf(), 0usize)]);
    while let Some((directory, depth)) = directories.pop_front() {
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let path = entry.path();
            let file_type = entry.file_type()?;
            if file_type.is_file()
                && path
                    .extension()
                    .is_some_and(|extension| extension == "desktop")
            {
                candidates.push(path);
            } else if depth < max_depth.saturating_sub(1) && file_type.is_dir() {
                directories.push_back((path, depth + 1));
            }
        }
    }
    candidates.sort();
    Ok(candidates.into_iter().next())
}

pub(super) fn write_entry(
    path: &Path,
    executable: &Path,
    name: &str,
    icon: &str,
    categories: &str,
    wmclass: &str,
) -> io::Result<()> {
    let mut lines = vec![
        "[Desktop Entry]".to_owned(),
        "Type=Application".to_owned(),
        format!("Name={}", escape_value(name)),
        format!(
            "Exec=\"{}\" %U",
            escape_value(&executable.to_string_lossy())
        ),
    ];
    if !icon.is_empty() {
        lines.push(format!("Icon={}", escape_value(icon)));
    }
    if !categories.is_empty() {
        lines.push(format!("Categories={}", escape_value(categories)));
    }
    if !wmclass.is_empty() {
        lines.push(format!("StartupWMClass={}", escape_value(wmclass)));
    }
    lines.push("Terminal=false".to_owned());
    lines.push("X-Silhouette-AppImage=true".to_owned());
    atomic_write(path, lines.join("\n").as_bytes())?;
    update_desktop_database(path.parent());
    Ok(())
}

pub(super) fn replace_desktop_line(path: &Path, key: &str, value: &str) -> io::Result<bool> {
    let body = fs::read_to_string(path)?;
    let prefix = format!("{key}=");
    let mut replaced = false;
    let mut lines = Vec::new();
    for line in body.lines() {
        if !replaced && line.starts_with(&prefix) {
            lines.push(format!("{prefix}{}", escape_value(value)));
            replaced = true;
        } else {
            lines.push(line.to_owned());
        }
    }
    if !replaced {
        lines.push(format!("{prefix}{}", escape_value(value)));
    }
    atomic_write(path, lines.join("\n").as_bytes())?;
    update_desktop_database(path.parent());
    Ok(replaced)
}

fn escape_value(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace(';', "\\;")
}

fn atomic_write(destination: &Path, bytes: &[u8]) -> io::Result<()> {
    let parent = destination
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "desktop file has no parent"))?;
    for _ in 0..32 {
        let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let temporary: PathBuf =
            parent.join(format!(".desktop.{}.{}.tmp", std::process::id(), sequence));
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
        {
            Ok(mut file) => {
                use std::io::Write;
                let result = file.write_all(bytes).and_then(|_| file.sync_all());
                drop(file);
                if let Err(error) = result {
                    let _ = fs::remove_file(&temporary);
                    return Err(error);
                }
                if let Err(error) = fs::rename(&temporary, destination) {
                    let _ = fs::remove_file(&temporary);
                    return Err(error);
                }
                return Ok(());
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "could not allocate a unique desktop-file temporary",
    ))
}

pub(super) fn update_desktop_database(directory: Option<&Path>) {
    let Some(directory) = directory else { return };
    let _ = Command::new("update-desktop-database")
        .arg(directory)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::apps::files::TempDir;

    #[test]
    fn desktop_search_respects_the_requested_depth() {
        let temp = TempDir::new("silhouette-desktop-search-test").unwrap();
        let root = temp.path();
        fs::write(root.join("root.desktop"), b"").unwrap();
        fs::create_dir_all(root.join("one")).unwrap();
        fs::write(root.join("one/child.desktop"), b"").unwrap();
        fs::create_dir_all(root.join("one/two")).unwrap();
        fs::write(root.join("one/two/deep.desktop"), b"").unwrap();

        assert_eq!(
            find_desktop_file(root, 2).unwrap(),
            Some(root.join("one/child.desktop"))
        );
    }
}
