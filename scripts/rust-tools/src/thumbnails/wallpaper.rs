use super::common::{
    atomic_write_bytes, decode_image_file, lock_cache, prepare_cache, thumbnail_png,
};
use crate::config::{cache_dir, expand_tilde, flags, home, state_dir};
use std::{
    collections::HashSet,
    fs, io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicUsize, Ordering},
    thread,
};

fn wallpaper_thumbnail_dir() -> PathBuf {
    if let Some(value) = flags()
        .get("wallpaperDir")
        .and_then(|value| value.as_str())
        .filter(|value| !value.is_empty())
    {
        return expand_tilde(value);
    }
    let resolved = state_dir().join("silhouette-wallpaper-dir");
    if let Ok(value) = fs::read_to_string(resolved) {
        let value = value.trim();
        if !value.is_empty() {
            return expand_tilde(value);
        }
    }
    home().join("Pictures")
}

fn is_wallpaper_thumbnail_source(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| matches!(extension.to_ascii_lowercase().as_str(), "jpg" | "png"))
}

fn wallpaper_output_name(path: &Path) -> Option<std::ffi::OsString> {
    let mut name = path.file_name()?.to_os_string();
    name.push(".png");
    Some(name)
}

fn collect_wallpapers(root: &Path) -> (Vec<PathBuf>, HashSet<std::ffi::OsString>, bool) {
    let mut pending = vec![root.to_path_buf()];
    let mut paths = Vec::new();
    let mut output_names = HashSet::new();
    let mut complete = true;
    while let Some(directory) = pending.pop() {
        let entries = match fs::read_dir(directory) {
            Ok(entries) => entries,
            Err(_) => {
                complete = false;
                continue;
            }
        };
        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => {
                    complete = false;
                    continue;
                }
            };
            let file_type = match entry.file_type() {
                Ok(file_type) => file_type,
                Err(_) => {
                    complete = false;
                    continue;
                }
            };
            if file_type.is_dir() {
                pending.push(entry.path());
            } else if file_type.is_file() && is_wallpaper_thumbnail_source(&entry.path()) {
                if let Some(name) = wallpaper_output_name(&entry.path()) {
                    output_names.insert(name);
                }
                paths.push(entry.path());
            }
        }
    }
    paths.sort();
    let mut seen_names = HashSet::new();
    paths.retain(|path| wallpaper_output_name(path).is_some_and(|name| seen_names.insert(name)));
    (paths, output_names, complete)
}

fn prune_wallpaper_cache(cache: &Path, keep: &HashSet<std::ffi::OsString>) -> io::Result<()> {
    let entries = fs::read_dir(cache)?.collect::<Result<Vec<_>, _>>()?;
    for entry in entries {
        if entry.file_type()?.is_file()
            && entry.path().extension().is_some_and(|ext| ext == "png")
            && !keep.contains(&entry.file_name())
        {
            fs::remove_file(entry.path())?;
        }
    }
    Ok(())
}

fn thumbnail_is_fresh(source: &Path, destination: &Path) -> bool {
    let Ok(source_time) = fs::metadata(source).and_then(|metadata| metadata.modified()) else {
        return false;
    };
    let Ok(destination_metadata) = fs::symlink_metadata(destination) else {
        return false;
    };
    destination_metadata.file_type().is_file()
        && destination_metadata.len() > 0
        && destination_metadata
            .modified()
            .is_ok_and(|destination_time| destination_time >= source_time)
}

fn generate_wallpaper_thumbnail(source: &Path, cache: &Path) {
    let Some(name) = wallpaper_output_name(source) else {
        return;
    };
    let destination = cache.join(name);
    if thumbnail_is_fresh(source, &destination) {
        return;
    }
    let result = decode_image_file(source).and_then(|image| thumbnail_png(&image, 512, 512));
    match result {
        Ok(bytes) => {
            if let Err(error) = atomic_write_bytes(cache, &destination, "wallpaper-thumb", &bytes) {
                eprintln!(
                    "wallpaper-thumbs: cannot write {}: {error}",
                    destination.display()
                );
            }
        }
        Err(error) => eprintln!(
            "wallpaper-thumbs: cannot decode {}: {error}",
            source.display()
        ),
    }
}

pub(crate) fn wallpaper_thumbnails() -> Result<(), Box<dyn std::error::Error>> {
    let root = wallpaper_thumbnail_dir();
    if !root.is_dir() {
        return Ok(());
    }
    let cache = cache_dir().join("silhouette-wp-thumbs");
    prepare_cache(&cache, false)?;
    let _lock = lock_cache(&cache, ".wallpaper-thumbs.lock")?;
    let (paths, output_names, complete) = collect_wallpapers(&root);
    if complete {
        prune_wallpaper_cache(&cache, &output_names)?;
    } else {
        eprintln!(
            "wallpaper-thumbs: source scan was incomplete; preserving existing cached thumbnails"
        );
    }

    let worker_count = std::thread::available_parallelism()
        .map_or(1, |count| count.get())
        .min(2)
        .min(paths.len());
    let next = AtomicUsize::new(0);
    thread::scope(|scope| {
        for _ in 0..worker_count {
            scope.spawn(|| loop {
                let index = next.fetch_add(1, Ordering::Relaxed);
                let Some(source) = paths.get(index) else {
                    break;
                };
                generate_wallpaper_thumbnail(source, &cache);
            });
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wallpaper_thumbnail_extensions_are_narrow_and_case_insensitive() {
        assert!(is_wallpaper_thumbnail_source(Path::new("Wallpaper.JPG")));
        assert!(is_wallpaper_thumbnail_source(Path::new("Wallpaper.PNG")));
        assert!(!is_wallpaper_thumbnail_source(Path::new("Wallpaper.JPEG")));
        assert!(!is_wallpaper_thumbnail_source(Path::new("movie.gif")));
    }
}
