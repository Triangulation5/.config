use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub(super) struct AppRecord {
    pub(super) name: String,
    #[serde(rename = "appimagePath")]
    pub(super) appimage_path: String,
    #[serde(rename = "iconPath")]
    pub(super) icon_path: String,
    #[serde(rename = "desktopPath")]
    pub(super) desktop_path: String,
    #[serde(rename = "appId")]
    pub(super) app_id: String,
}

pub(super) struct AppPaths {
    pub(super) apps_dir: PathBuf,
    pub(super) desktop_dir: PathBuf,
    pub(super) icon_dir: PathBuf,
    pub(super) registry: PathBuf,
}

impl AppPaths {
    pub(super) fn new() -> Result<Self, String> {
        let data_home = env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))
            .ok_or_else(|| "HOME or XDG_DATA_HOME must be set".to_owned())?;
        let paths = Self {
            apps_dir: data_home.join("appimages"),
            desktop_dir: data_home.join("applications"),
            icon_dir: data_home.join("silhouette/appimages"),
            registry: data_home.join("silhouette/appimages.json"),
        };
        fs::create_dir_all(&paths.apps_dir)
            .map_err(|error| format!("cannot create {}: {error}", paths.apps_dir.display()))?;
        fs::create_dir_all(&paths.desktop_dir)
            .map_err(|error| format!("cannot create {}: {error}", paths.desktop_dir.display()))?;
        fs::create_dir_all(&paths.icon_dir)
            .map_err(|error| format!("cannot create {}: {error}", paths.icon_dir.display()))?;
        if !paths.registry.exists() {
            atomic_write(&paths.registry, b"{}")?;
        }
        Ok(paths)
    }

    pub(super) fn read(&self) -> Result<BTreeMap<String, AppRecord>, String> {
        let body = fs::read(&self.registry)
            .map_err(|error| format!("cannot read {}: {error}", self.registry.display()))?;
        serde_json::from_slice(&body)
            .map_err(|error| format!("invalid app registry {}: {error}", self.registry.display()))
    }

    pub(super) fn write(&self, registry: &BTreeMap<String, AppRecord>) -> Result<(), String> {
        let body = serde_json::to_vec(registry)
            .map_err(|error| format!("cannot serialize app registry: {error}"))?;
        atomic_write(&self.registry, &body)
    }

    pub(super) fn owns_path(&self, directory: &Path, path: &Path) -> bool {
        let Ok(directory) = directory.canonicalize() else {
            return false;
        };
        let Ok(path) = path.canonicalize() else {
            return false;
        };
        path != directory && path.starts_with(directory)
    }
}

fn atomic_write(destination: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = destination
        .parent()
        .ok_or_else(|| format!("{} has no parent directory", destination.display()))?;
    for _ in 0..32 {
        let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let temporary = parent.join(format!(".registry.{}.{}.tmp", std::process::id(), sequence));
        let mut file = match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
        {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(format!("cannot create {}: {error}", temporary.display()));
            }
        };
        let result = file.write_all(bytes).and_then(|_| file.sync_all());
        drop(file);
        if let Err(error) = result {
            let _ = fs::remove_file(&temporary);
            return Err(format!("cannot write {}: {error}", temporary.display()));
        }
        if let Err(error) = fs::rename(&temporary, destination) {
            let _ = fs::remove_file(&temporary);
            return Err(format!("cannot replace {}: {error}", destination.display()));
        }
        return Ok(());
    }
    Err("could not allocate a unique registry temporary file".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn owned_path_check_rejects_the_managed_root_itself() {
        let root = env::temp_dir().join(format!("silhouette-app-path-test-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let child = root.join("child");
        fs::write(&child, b"test").unwrap();
        let paths = AppPaths {
            apps_dir: root.clone(),
            desktop_dir: root.clone(),
            icon_dir: root.clone(),
            registry: root.join("registry.json"),
        };
        assert!(!paths.owns_path(&root, &root));
        assert!(paths.owns_path(&root, &child));
        fs::remove_dir_all(root).unwrap();
    }
}
