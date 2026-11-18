use crate::config::{cache_dir, client, resolve_dir};
use sha1::{Digest, Sha1};
use std::{
    env, fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

fn sha1_24(text: &str) -> String {
    let mut hasher = Sha1::new();
    hasher.update(text.as_bytes());
    format!("{:x}", hasher.finalize())[..24].to_string()
}

fn prune_thumbs(base: &Path) {
    let max: u64 = env::var("WH_THUMB_MAX_MB")
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|v| *v > 0)
        .unwrap_or(20);
    let mut entries: Vec<(SystemTime, PathBuf)> = fs::read_dir(base)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            if path
                .file_name()
                .and_then(|v| v.to_str())
                .is_some_and(|v| v.starts_with('.'))
            {
                return None;
            }
            Some((fs::metadata(&path).ok()?.modified().ok()?, path))
        })
        .collect();
    entries.sort_by_key(|v| v.0);
    let mut total: u64 = entries
        .iter()
        .filter_map(|(_, p)| fs::metadata(p).ok())
        .map(|m| m.len())
        .sum();
    for (_, path) in entries {
        if total <= max * 1024 * 1024 {
            break;
        }
        if let Ok(metadata) = fs::metadata(&path) {
            let _ = fs::remove_file(&path);
            total = total.saturating_sub(metadata.len());
        }
    }
}

pub(crate) fn thumbget(url: &str) -> Option<PathBuf> {
    let base = cache_dir().join("silhouette/wh-thumbs");
    fs::create_dir_all(&base).ok()?;
    let digest = sha1_24(url);
    let cache = base.join(&digest);
    if fs::metadata(&cache).is_ok_and(|m| m.len() > 0) {
        return Some(cache);
    }
    if !super::wallhaven::wh_gate(false) {
        return None;
    }
    let bytes = client(25)
        .get(url)
        .header("Referer", "https://wallhaven.cc/")
        .send()
        .ok()?
        .error_for_status()
        .ok()?
        .bytes()
        .ok()?;
    if bytes.is_empty() {
        return None;
    }
    fs::write(&cache, bytes).ok()?;
    prune_thumbs(&base);
    Some(cache)
}

pub(crate) fn download(url: &str) -> Option<PathBuf> {
    if super::providers::is_blocked(url) {
        return None;
    }
    let dir = resolve_dir();
    fs::create_dir_all(&dir).ok()?;
    if url.starts_with("https://w.wallhaven.cc/") {
        if !super::wallhaven::wh_gate(false) {
            return None;
        }
        let parsed = url::Url::parse(url).ok()?;
        let filename = parsed.path_segments()?.next_back()?;
        let bytes = client(600)
            .get(url)
            .header("Referer", "https://wallhaven.cc/")
            .send()
            .ok()?
            .error_for_status()
            .ok()?
            .bytes()
            .ok()?;
        let out = dir.join(filename);
        fs::write(&out, bytes).ok()?;
        return Some(out);
    }
    if url.starts_with("https://go.moewalls.com/download.php") {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
        let out = dir.join(format!("moewalls-{stamp}.mp4"));
        let bytes = client(600)
            .get(url)
            .header("Referer", "https://moewalls.com/")
            .send()
            .ok()?
            .error_for_status()
            .ok()?
            .bytes()
            .ok()?;
        fs::write(&out, bytes).ok()?;
        return Some(out);
    }
    let bytes = client(60)
        .get(url)
        .header("Referer", "https://duckduckgo.com/")
        .send()
        .ok()?
        .error_for_status()
        .ok()?
        .bytes()
        .ok()?;
    let image = image::load_from_memory(&bytes).ok()?;
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
    let random: u32 = rand::random();
    let out = dir.join(format!("ddg-{stamp}-{random}.png"));
    image.save(&out).ok()?;
    Some(out)
}
