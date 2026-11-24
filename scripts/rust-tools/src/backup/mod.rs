mod archive;

use archive::{
    copy_file, copy_tree, create_staging_directory, extract_archive, state_files, unix_seconds,
    validate_archive, write_archive,
};
use chrono::Local;
use serde_json::{json, Value};
use std::{
    env, fs,
    fs::OpenOptions,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

pub(super) const SHELL_MEMBER: &str = "silhouette-shell";
pub(super) const FLAG_MEMBER: &str = "flags.json";
pub(super) const EVENT_MEMBER: &str = "events.json";
pub(super) const WALLPAPER_MEMBER: &str = "silhouette-wallpaper";
pub(super) const LEGACY_WALLPAPER_MEMBER: &str = "ricelin-wallpaper";
const PREFIX: &str = "silhouette-";
const SUFFIX: &str = ".tar.gz";
static BACKUP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub(super) struct Paths {
    pub(super) shell: PathBuf,
    pub(super) state: PathBuf,
    pub(super) dir: PathBuf,
}

pub(crate) fn run(
    action: &str,
    name: Option<&str>,
    shell: Option<&Path>,
    state: Option<&Path>,
    dir: Option<&Path>,
) -> bool {
    let result =
        resolve_paths(shell, state, dir).and_then(|paths| run_action(action, name, &paths));
    let (payload, success) = match result {
        Ok(payload) => (payload, true),
        Err(message) => (
            json!({
                "status": "error",
                "error": message
            }),
            false,
        ),
    };
    let mut stdout = io::stdout().lock();
    serde_json::to_writer(&mut stdout, &payload).is_ok()
        && stdout.write_all(b"\n").is_ok()
        && success
}

fn resolve_paths(
    shell: Option<&Path>,
    state: Option<&Path>,
    dir: Option<&Path>,
) -> Result<Paths, String> {
    let home = env::var_os("HOME").map(PathBuf::from);
    let state_home = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|path| path.join(".local/state")));
    let state = match state
        .map(Path::to_path_buf)
        .or_else(|| env::var_os("SILHOUETTE_STATE_DIR").map(PathBuf::from))
    {
        Some(state) => state,
        None => state_home
            .map(|path| path.join("silhouette"))
            .ok_or_else(|| "HOME or XDG_STATE_HOME must be set".to_owned())?,
    };
    let shell = match shell
        .map(Path::to_path_buf)
        .or_else(|| env::var_os("SILHOUETTE_SHELL_DIR").map(PathBuf::from))
    {
        Some(shell) => shell,
        None => home
            .as_ref()
            .map(|path| path.join(".config/quickshell/silhouette-shell"))
            .ok_or_else(|| "HOME must be set when --shell is not provided".to_owned())?,
    };
    let default_dir = state.join("backups");
    let dir = dir
        .map(Path::to_path_buf)
        .or_else(|| env::var_os("SILHOUETTE_BACKUP_DIR").map(PathBuf::from))
        .unwrap_or(default_dir);

    Ok(Paths {
        shell: absolute(shell)?,
        state: absolute(state)?,
        dir: absolute(dir)?,
    })
}

fn absolute(path: PathBuf) -> Result<PathBuf, String> {
    if path.is_absolute() {
        Ok(path)
    } else {
        env::current_dir()
            .map(|current| current.join(path))
            .map_err(|error| format!("Could not resolve path: {error}"))
    }
}

fn run_action(action: &str, name: Option<&str>, paths: &Paths) -> Result<Value, String> {
    match action {
        "create" => create(paths),
        "list" => list(paths),
        "restore" | "remove" => {
            let name = name
                .filter(|name| !name.is_empty())
                .ok_or_else(|| format!("name the backup to {action}"))?;
            let archive = resolve_archive(&paths.dir, name)
                .ok_or_else(|| format!("no backup named {name} in {}", paths.dir.display()))?;
            if action == "restore" {
                restore(paths, &archive, name)
            } else {
                remove(&archive, name)
            }
        }
        _ => Err(format!("unknown backup action: {action}")),
    }
}

fn create(paths: &Paths) -> Result<Value, String> {
    let timestamp = Local::now().format("%Y-%m-%dT%H-%M-%S").to_string();
    create_at(paths, &timestamp)
}

fn create_at(paths: &Paths, timestamp: &str) -> Result<Value, String> {
    let shell_metadata = match fs::symlink_metadata(&paths.shell) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Err(format!("{} is not a directory", paths.shell.display()));
        }
        Err(error) => {
            return Err(format!("Could not read {}: {error}", paths.shell.display()));
        }
    };
    if !shell_metadata.is_dir() || shell_metadata.file_type().is_symlink() {
        return Err(format!("{} is not a directory", paths.shell.display()));
    }

    fs::create_dir_all(&paths.dir)
        .map_err(|error| format!("Could not write {}: {error}", paths.dir.display()))?;

    let (name, archive_path, partial_path, partial_file) = loop {
        let sequence = BACKUP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let name = format!(
            "{PREFIX}{timestamp}-{}-{sequence}{SUFFIX}",
            std::process::id()
        );
        let archive_path = paths.dir.join(&name);
        let partial_path = PathBuf::from(format!("{}.part", archive_path.display()));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&partial_path)
        {
            Ok(file) if archive_path.exists() => {
                drop(file);
                fs::remove_file(&partial_path).map_err(|error| {
                    format!("Could not clear {}: {error}", partial_path.display())
                })?;
            }
            Ok(file) => break (name, archive_path, partial_path, file),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(format!(
                    "Could not write {}: {error}",
                    archive_path.display()
                ));
            }
        }
    };

    let written = write_archive(partial_file, paths).map_err(|error| {
        let _ = fs::remove_file(&partial_path);
        format!("Could not write {}: {error}", archive_path.display())
    })?;
    fs::rename(&partial_path, &archive_path).map_err(|error| {
        let _ = fs::remove_file(&partial_path);
        format!("Could not write {}: {error}", archive_path.display())
    })?;
    let metadata = fs::metadata(&archive_path)
        .map_err(|error| format!("Could not read {}: {error}", archive_path.display()))?;
    Ok(json!({
        "status": "ok",
        "name": name,
        "path": archive_path.to_string_lossy(),
        "bytes": metadata.len(),
        "files": written,
        "created": unix_seconds(metadata.modified().unwrap_or(SystemTime::now()))
    }))
}

fn list(paths: &Paths) -> Result<Value, String> {
    let entries = match fs::read_dir(&paths.dir) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(json!({ "status": "ok", "backups": [] }));
        }
        Err(error) => return Err(format!("Could not read {}: {error}", paths.dir.display())),
    };
    let mut backups = Vec::new();
    for entry in entries {
        let entry =
            entry.map_err(|error| format!("Could not read {}: {error}", paths.dir.display()))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !is_backup_name(&name) {
            continue;
        }
        let metadata = entry
            .metadata()
            .map_err(|error| format!("Could not read {}: {error}", entry.path().display()))?;
        if !metadata.is_file() {
            continue;
        }
        backups.push(json!({
            "name": name,
            "path": entry.path().to_string_lossy(),
            "bytes": metadata.len(),
            "created": unix_seconds(metadata.modified().unwrap_or(UNIX_EPOCH))
        }));
    }
    backups.sort_by(|left, right| {
        right["created"]
            .as_u64()
            .cmp(&left["created"].as_u64())
            .then_with(|| right["name"].as_str().cmp(&left["name"].as_str()))
    });
    Ok(json!({ "status": "ok", "backups": backups }))
}

fn is_backup_name(name: &str) -> bool {
    name.starts_with(PREFIX) && name.ends_with(SUFFIX)
}

fn resolve_archive(directory: &Path, name: &str) -> Option<PathBuf> {
    if Path::new(name).file_name().and_then(|value| value.to_str()) != Some(name)
        || !is_backup_name(name)
    {
        return None;
    }
    let path = directory.join(name);
    fs::metadata(&path)
        .ok()
        .filter(|metadata| metadata.is_file())?;
    Some(path)
}

fn restore(paths: &Paths, archive_path: &Path, name: &str) -> Result<Value, String> {
    let staging = create_staging_directory()?;
    validate_archive(archive_path).map_err(|error| contextual_restore_error(name, error))?;
    extract_archive(archive_path, &staging.0)
        .map_err(|error| contextual_restore_error(name, error))?;

    let shell_tree = staging.0.join(SHELL_MEMBER);
    let files = if shell_tree.is_dir() {
        copy_tree(&shell_tree, &paths.shell)
            .map_err(|error| format!("Could not restore {name}: {error}"))?
    } else {
        0
    };
    let mut flags = false;
    for (member, target) in state_files(&paths.state) {
        let source = staging.0.join(member);
        let source = if !source.is_file() && member == WALLPAPER_MEMBER {
            staging.0.join(LEGACY_WALLPAPER_MEMBER)
        } else {
            source
        };
        if !source.is_file() {
            continue;
        }
        let parent = target
            .parent()
            .ok_or_else(|| format!("Could not restore {name}: invalid target path"))?;
        fs::create_dir_all(parent).map_err(|error| format!("Could not restore {name}: {error}"))?;
        copy_file(&source, &target)
            .map_err(|error| format!("Could not restore {name}: {error}"))?;
        flags |= member == FLAG_MEMBER;
    }
    Ok(json!({
        "status": "ok",
        "name": name,
        "files": files,
        "flags": flags
    }))
}

fn contextual_restore_error(name: &str, error: String) -> String {
    if error.starts_with("The archive holds something this script did not write:") {
        error
    } else {
        format!("Could not restore {name}: {error}")
    }
}

fn remove(archive: &Path, name: &str) -> Result<Value, String> {
    fs::remove_file(archive)
        .map_err(|error| format!("Could not delete {}: {error}", archive.display()))?;
    Ok(json!({ "status": "ok", "name": name }))
}

#[cfg(test)]
mod tests {
    use super::archive::inside;
    use super::*;
    use flate2::{write::GzEncoder, Compression};
    use std::{fs::File, io::Cursor, path::Path};
    use tar::{Builder, EntryType, Header};

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new() -> Self {
            let path = env::temp_dir().join(format!(
                "silhouette-backup-test-{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos()
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn paths(root: &Path) -> Paths {
        Paths {
            shell: root.join("shell"),
            state: root.join("state/silhouette"),
            dir: root.join("backups"),
        }
    }

    #[test]
    fn backup_round_trip_preserves_new_files_and_skips_caches() {
        let temp = TestDirectory::new();
        let paths = paths(&temp.0);
        fs::create_dir_all(paths.shell.join("__pycache__")).unwrap();
        fs::create_dir_all(&paths.state).unwrap();
        fs::write(paths.shell.join("app.qml"), "original").unwrap();
        fs::write(paths.shell.join("__pycache__/stale.pyc"), "cache").unwrap();
        fs::write(paths.state.join(FLAG_MEMBER), "{}").unwrap();
        fs::write(paths.state.join(EVENT_MEMBER), "[]").unwrap();
        fs::write(paths.state.parent().unwrap().join(WALLPAPER_MEMBER), "path").unwrap();

        let created = create(&paths).unwrap();
        assert_eq!(created["files"], 4);
        let name = created["name"].as_str().unwrap();

        fs::write(paths.shell.join("app.qml"), "changed").unwrap();
        fs::write(paths.shell.join("added-after-backup.qml"), "keep").unwrap();
        fs::remove_dir_all(paths.shell.join("__pycache__")).unwrap();
        let restored = restore(&paths, &resolve_archive(&paths.dir, name).unwrap(), name).unwrap();
        assert_eq!(restored["files"], 1);
        assert_eq!(restored["flags"], true);
        assert_eq!(
            fs::read_to_string(paths.shell.join("app.qml")).unwrap(),
            "original"
        );
        assert_eq!(
            fs::read_to_string(paths.shell.join("added-after-backup.qml")).unwrap(),
            "keep"
        );
        assert!(!paths.shell.join("__pycache__").exists());
        assert_eq!(
            list(&paths).unwrap()["backups"].as_array().unwrap().len(),
            1
        );
        remove(&paths.dir.join(name), name).unwrap();
        assert!(list(&paths).unwrap()["backups"]
            .as_array()
            .unwrap()
            .is_empty());
    }

    #[test]
    fn backups_with_the_same_timestamp_get_distinct_names() {
        let temp = TestDirectory::new();
        let paths = paths(&temp.0);
        fs::create_dir_all(&paths.shell).unwrap();
        fs::write(paths.shell.join("app.qml"), "original").unwrap();

        let first = create_at(&paths, "2026-11-20T17-33-04").unwrap();
        fs::write(paths.shell.join("app.qml"), "updated").unwrap();
        let second = create_at(&paths, "2026-11-20T17-33-04").unwrap();

        let first_name = first["name"].as_str().unwrap();
        let second_name = second["name"].as_str().unwrap();
        assert_ne!(first_name, second_name);
        assert_eq!(
            list(&paths).unwrap()["backups"].as_array().unwrap().len(),
            2
        );
        assert!(fs::metadata(paths.dir.join(first_name)).unwrap().len() > 0);
        assert!(fs::metadata(paths.dir.join(second_name)).unwrap().len() > 0);
    }

    #[test]
    fn restore_rejects_unowned_archive_members() {
        let temp = TestDirectory::new();
        let paths = paths(&temp.0);
        fs::create_dir_all(&paths.dir).unwrap();
        let archive_path = paths.dir.join(format!("{PREFIX}unsafe{SUFFIX}"));
        let encoder = GzEncoder::new(File::create(&archive_path).unwrap(), Compression::default());
        let mut archive = Builder::new(encoder);
        let mut header = Header::new_gnu();
        header.set_entry_type(EntryType::Regular);
        header.set_size(4);
        header.set_cksum();
        archive
            .append_data(&mut header, "outside.txt", Cursor::new(b"oops"))
            .unwrap();
        archive.into_inner().unwrap().finish().unwrap();

        let result = restore(
            &paths,
            &archive_path,
            archive_path.file_name().unwrap().to_str().unwrap(),
        );
        assert!(result.unwrap_err().contains("did not write"));
        assert!(!inside(Path::new("../escape"), EntryType::Regular));
        assert!(!temp.0.join("outside.txt").exists());
    }
}
