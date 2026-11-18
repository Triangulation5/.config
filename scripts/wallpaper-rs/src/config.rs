use reqwest::blocking::Client;
use std::{
    env, fs,
    path::{Path, PathBuf},
    time::Duration,
};

pub(crate) const UA: &str = "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/126.0";

pub(crate) fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

pub(crate) fn state_dir() -> PathBuf {
    env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/state"))
}

pub(crate) fn cache_dir() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".cache"))
}

pub(crate) fn script_dir() -> PathBuf {
    let exe = env::current_exe().unwrap_or_default();
    if let Some(parent) = exe.parent() {
        if parent.file_name().and_then(|v| v.to_str()) == Some("bin") {
            if let Some(root) = parent.parent() {
                return root.to_path_buf();
            }
        }
        return parent.to_path_buf();
    }
    home().join(".config/scripts")
}

pub(crate) fn client(timeout: u64) -> Client {
    Client::builder()
        .timeout(Duration::from_secs(timeout))
        .user_agent(UA)
        .build()
        .unwrap_or_else(|_| Client::new())
}

pub(crate) fn expand_tilde(value: &str) -> PathBuf {
    if value == "~" {
        home()
    } else if let Some(rest) = value.strip_prefix("~/") {
        home().join(rest)
    } else {
        PathBuf::from(value)
    }
}

pub(crate) fn flags() -> serde_json::Value {
    fs::read_to_string(state_dir().join("silhouette/flags.json"))
        .ok()
        .and_then(|body| serde_json::from_str(&body).ok())
        .unwrap_or_else(|| serde_json::json!({}))
}

pub(crate) fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|v| v.to_str())
        .is_some_and(|ext| {
            matches!(
                ext.to_ascii_lowercase().as_str(),
                "jpg" | "jpeg" | "png" | "gif" | "webp"
            )
        })
}

pub(crate) fn resolve_dir() -> PathBuf {
    if let Some(value) = flags()
        .get("wallpaperDir")
        .and_then(|v| v.as_str())
        .filter(|v| !v.is_empty())
    {
        return expand_tilde(value);
    }
    if let Ok(value) = fs::read_to_string(state_dir().join("silhouette-wallpaper-dir")) {
        let value = value.trim();
        if !value.is_empty() {
            return expand_tilde(value);
        }
    }
    let candidates = [
        home().join("Pictures"),
        home().join("Pictures/rice-wallpapers"),
        home().join("Pictures/Wallpapers"),
        home().join("Pictures/wallpapers"),
        home().join("Wallpapers"),
        home().join("wallpapers"),
    ];
    for candidate in candidates {
        if !candidate.is_dir() {
            continue;
        }
        let mut count = 0;
        if let Ok(entries) = fs::read_dir(&candidate) {
            for entry in entries.flatten() {
                if entry.path().is_file() && is_image(&entry.path()) {
                    count += 1;
                    if count >= 2 {
                        return candidate;
                    }
                }
            }
        }
    }
    home().join("Pictures")
}
