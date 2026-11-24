use super::{
    Paths, EVENT_MEMBER, FLAG_MEMBER, LEGACY_WALLPAPER_MEMBER, SHELL_MEMBER, WALLPAPER_MEMBER,
};
use flate2::{read::GzDecoder, write::GzEncoder, Compression};
use std::{
    env, fs,
    fs::{File, FileTimes},
    io::{self, Write},
    os::unix::fs::PermissionsExt,
    path::{Component, Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
use tar::{Archive, Builder, EntryType, Header};

pub(super) struct TemporaryDirectory(pub(super) PathBuf);

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub(super) fn write_archive(file: File, paths: &Paths) -> Result<usize, String> {
    let encoder = GzEncoder::new(file, Compression::default());
    let mut archive = Builder::new(encoder);
    let mut files = 0;
    let shell_root = Path::new(SHELL_MEMBER);
    append_directory(&mut archive, &paths.shell, shell_root).map_err(|error| error.to_string())?;
    append_tree(&mut archive, &paths.shell, shell_root, &mut files)
        .map_err(|error| error.to_string())?;

    for (member, source) in state_files(&paths.state) {
        if fs::symlink_metadata(&source).is_ok_and(|metadata| metadata.is_file())
            && append_file(&mut archive, &source, Path::new(member))
                .map_err(|error| error.to_string())?
        {
            files += 1;
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
            if name == "__pycache__" || name == "target" {
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

pub(super) fn unix_seconds(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn is_bytecode(name: &std::ffi::OsStr) -> bool {
    let name = name.to_string_lossy();
    name.ends_with(".pyc") || name.ends_with(".pyo")
}

pub(super) fn state_files(state: &Path) -> [(&'static str, PathBuf); 3] {
    let beside = state.parent().unwrap_or(state);
    [
        (FLAG_MEMBER, state.join(FLAG_MEMBER)),
        (EVENT_MEMBER, state.join(EVENT_MEMBER)),
        (WALLPAPER_MEMBER, beside.join(WALLPAPER_MEMBER)),
    ]
}

pub(super) fn create_staging_directory() -> Result<TemporaryDirectory, String> {
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

pub(super) fn validate_archive(path: &Path) -> Result<(), String> {
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

pub(super) fn inside(member: &Path, entry_type: EntryType) -> bool {
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

pub(super) fn extract_archive(path: &Path, staging: &Path) -> Result<(), String> {
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

pub(super) fn copy_tree(source: &Path, target: &Path) -> Result<usize, String> {
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

pub(super) fn copy_file(source: &Path, target: &Path) -> io::Result<()> {
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
