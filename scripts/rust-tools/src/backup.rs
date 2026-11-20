use chrono::Local;
use flate2::{read::GzDecoder, write::GzEncoder, Compression};
use serde_json::{json, Value};
use std::{
    env, fs,
    fs::{File, FileTimes, OpenOptions},
    io::{self, Write},
    os::unix::fs::PermissionsExt,
    path::{Component, Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};
use tar::{Archive, Builder, EntryType, Header};

const SHELL_MEMBER: &str = "silhouette-shell";
const FLAG_MEMBER: &str = "flags.json";
const EVENT_MEMBER: &str = "events.json";
const WALLPAPER_MEMBER: &str = "silhouette-wallpaper";
const LEGACY_WALLPAPER_MEMBER: &str = "ricelin-wallpaper";
const PREFIX: &str = "silhouette-";
const SUFFIX: &str = ".tar.gz";
static BACKUP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct Paths {
    shell: PathBuf,
    state: PathBuf,
    dir: PathBuf,
}

struct TemporaryDirectory(PathBuf);

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
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

fn write_archive(file: File, paths: &Paths) -> Result<usize, String> {
    let encoder = GzEncoder::new(file, Compression::default());
    let mut archive = Builder::new(encoder);
    let mut files = 0;
    let shell_root = Path::new(SHELL_MEMBER);
    append_directory(&mut archive, &paths.shell, shell_root).map_err(|error| error.to_string())?;
    append_tree(&mut archive, &paths.shell, shell_root, &mut files)
        .map_err(|error| error.to_string())?;

    for (member, source) in state_files(&paths.state) {
        if fs::symlink_metadata(&source).is_ok_and(|metadata| metadata.is_file()) {
            if append_file(&mut archive, &source, Path::new(member))
                .map_err(|error| error.to_string())?
            {
                files += 1;
            }
        }
    }

    let encoder = archive.into_inner().map_err(|error| error.to_string())?;
    let file = encoder.finish().map_err(|error| error.to_string())?;
    file.sync_all().map_err(|error| error.to_string())?;
    Ok(files)
}

fn append_tree<W: Write>(
    archive: &mut Builder<W>,
    source: &Path,
    member: &Path,
    files: &mut usize,
) -> io::Result<()> {
    let mut entries = fs::read_dir(source)?.collect::<Result<Vec<_>, _>>()?;
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        let name = entry.file_name();
        if metadata.file_type().is_symlink() {
            continue;
        }
        if metadata.is_dir() {
            if name == "__pycache__" {
                continue;
            }
            let child_member = member.join(&name);
            append_directory(archive, &path, &child_member)?;
            append_tree(archive, &path, &child_member, files)?;
        } else if metadata.is_file() && !is_bytecode(&name) {
            let child_member = member.join(name);
            if append_file(archive, &path, &child_member)? {
                *files += 1;
            }
        }
    }
    Ok(())
}

fn append_directory<W: Write>(
    archive: &mut Builder<W>,
    source: &Path,
    member: &Path,
) -> io::Result<()> {
    let metadata = fs::symlink_metadata(source)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Ok(());
    }
    let mut header = Header::new_gnu();
    header.set_entry_type(EntryType::Directory);
    header.set_mode(metadata.permissions().mode());
    header.set_size(0);
    header.set_mtime(metadata_mtime(&metadata));
    header.set_cksum();
    archive.append_data(&mut header, member, io::empty())
}

fn append_file<W: Write>(
    archive: &mut Builder<W>,
    source: &Path,
    member: &Path,
) -> io::Result<bool> {
    let mut file = File::open(source)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Ok(false);
    }
    let mut header = Header::new_gnu();
    header.set_entry_type(EntryType::Regular);
    header.set_mode(metadata.permissions().mode());
    header.set_size(metadata.len());
    header.set_mtime(metadata_mtime(&metadata));
    header.set_cksum();
    archive.append_data(&mut header, member, &mut file)?;
    Ok(true)
}

fn metadata_mtime(metadata: &fs::Metadata) -> u64 {
    metadata
        .modified()
        .ok()
        .map(unix_seconds)
        .unwrap_or_default()
}

fn unix_seconds(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn is_bytecode(name: &std::ffi::OsStr) -> bool {
    let name = name.to_string_lossy();
    name.ends_with(".pyc") || name.ends_with(".pyo")
}

fn state_files(state: &Path) -> [(&'static str, PathBuf); 3] {
    let beside = state.parent().unwrap_or(state);
    [
        (FLAG_MEMBER, state.join(FLAG_MEMBER)),
        (EVENT_MEMBER, state.join(EVENT_MEMBER)),
        (WALLPAPER_MEMBER, beside.join(WALLPAPER_MEMBER)),
    ]
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

fn create_staging_directory() -> Result<TemporaryDirectory, String> {
    let parent = env::temp_dir();
    for attempt in 0..100 {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let path = parent.join(format!(
            "silhouette-restore-{}-{nonce}-{attempt}",
            std::process::id()
        ));
        match fs::create_dir(&path) {
            Ok(()) => return Ok(TemporaryDirectory(path)),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("Could not prepare restore: {error}")),
        }
    }
    Err("Could not prepare restore: temporary paths are busy".to_owned())
}

fn validate_archive(path: &Path) -> Result<(), String> {
    let file = File::open(path).map_err(|error| error.to_string())?;
    let mut archive = Archive::new(GzDecoder::new(file));
    let entries = archive.entries().map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let member = entry.path().map_err(|error| error.to_string())?;
        if !inside(&member, entry.header().entry_type()) {
            return Err(format!(
                "The archive holds something this script did not write: {}",
                member.to_string_lossy()
            ));
        }
    }
    Ok(())
}

fn inside(member: &Path, entry_type: EntryType) -> bool {
    if member.as_os_str().is_empty()
        || member.components().any(|component| {
            matches!(
                component,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        })
    {
        return false;
    }
    let components = member.components().collect::<Vec<_>>();
    if components
        .iter()
        .any(|component| !matches!(component, Component::Normal(_)))
    {
        return false;
    }
    let Some(Component::Normal(top)) = components.first() else {
        return false;
    };
    if *top == SHELL_MEMBER {
        if components.len() == 1 {
            entry_type.is_dir()
        } else {
            entry_type.is_dir() || entry_type.is_file()
        }
    } else {
        components.len() == 1
            && matches!(
                top.to_str(),
                Some(FLAG_MEMBER | EVENT_MEMBER | WALLPAPER_MEMBER | LEGACY_WALLPAPER_MEMBER)
            )
            && entry_type.is_file()
    }
}

fn extract_archive(path: &Path, staging: &Path) -> Result<(), String> {
    let file = File::open(path).map_err(|error| error.to_string())?;
    let mut archive = Archive::new(GzDecoder::new(file));
    let entries = archive.entries().map_err(|error| error.to_string())?;
    for entry in entries {
        let mut entry = entry.map_err(|error| error.to_string())?;
        let member = entry
            .path()
            .map_err(|error| error.to_string())?
            .into_owned();
        if !inside(&member, entry.header().entry_type()) {
            return Err(format!(
                "The archive holds something this script did not write: {}",
                member.to_string_lossy()
            ));
        }
        if !entry
            .unpack_in(staging)
            .map_err(|error| error.to_string())?
        {
            return Err(format!(
                "The archive holds something this script did not write: {}",
                member.to_string_lossy()
            ));
        }
    }
    Ok(())
}

fn copy_tree(source: &Path, target: &Path) -> Result<usize, String> {
    fs::create_dir_all(target).map_err(|error| error.to_string())?;
    let mut files = 0;
    copy_directory(source, source, target, &mut files)?;
    Ok(files)
}

fn copy_directory(
    root: &Path,
    source: &Path,
    target: &Path,
    files: &mut usize,
) -> Result<(), String> {
    let mut entries = fs::read_dir(source)
        .map_err(|error| error.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())?;
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        let source_path = entry.path();
        let metadata = fs::symlink_metadata(&source_path).map_err(|error| error.to_string())?;
        let name = entry.file_name();
        if metadata.file_type().is_symlink() {
            continue;
        }
        if metadata.is_dir() {
            if name == "__pycache__" {
                continue;
            }
            let relative = source_path
                .strip_prefix(root)
                .map_err(|error| error.to_string())?;
            let target_path = target.join(relative);
            fs::create_dir_all(&target_path).map_err(|error| error.to_string())?;
            copy_directory(root, &source_path, target, files)?;
        } else if metadata.is_file() && !is_bytecode(&name) {
            let relative = source_path
                .strip_prefix(root)
                .map_err(|error| error.to_string())?;
            let target_path = target.join(relative);
            copy_file(&source_path, &target_path).map_err(|error| error.to_string())?;
            *files += 1;
        }
    }
    Ok(())
}

fn copy_file(source: &Path, target: &Path) -> io::Result<()> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::copy(source, target)?;
    let metadata = fs::metadata(source)?;
    fs::set_permissions(target, metadata.permissions())?;
    if let Ok(modified) = metadata.modified() {
        File::open(target)?.set_times(FileTimes::new().set_modified(modified))?;
    }
    Ok(())
}

fn remove(archive: &Path, name: &str) -> Result<Value, String> {
    fs::remove_file(archive)
        .map_err(|error| format!("Could not delete {}: {error}", archive.display()))?;
    Ok(json!({ "status": "ok", "name": name }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io::Cursor, path::Path};

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
