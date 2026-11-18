use super::common::{lock_cache, prepare_cache};
use crate::config::cache_dir;
use std::{
    collections::{HashSet, VecDeque},
    ffi::OsString,
    fs, io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    thread,
};

static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

fn output_name(source: &Path) -> Option<OsString> {
    let name = source.file_name()?.to_str()?;
    let stem = name.strip_suffix(".mp4")?;
    Some(OsString::from(format!("{stem}.jpg")))
}

fn is_recording(source: &Path) -> bool {
    source
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("recording_") && name.ends_with(".mp4"))
}

fn needs_update(source: &Path, thumbnail: &Path) -> bool {
    let Ok(thumbnail_metadata) = fs::metadata(thumbnail) else {
        return true;
    };
    if thumbnail_metadata.len() == 0 {
        return true;
    }

    match (fs::metadata(source), thumbnail_metadata.modified()) {
        (Ok(source_metadata), Ok(thumbnail_time)) => source_metadata
            .modified()
            .map(|source_time| source_time > thumbnail_time)
            .unwrap_or(true),
        _ => true,
    }
}

fn unique_temp_path(cache: &Path) -> PathBuf {
    let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    cache.join(format!(
        ".rec-thumb.{}.{}.jpg",
        std::process::id(),
        sequence
    ))
}

fn run_ffmpeg(source: &Path, temporary: &Path, seek: u64) -> io::Result<bool> {
    let status = Command::new("ffmpeg")
        .args(["-hide_banner", "-loglevel", "error", "-nostdin", "-y"])
        .arg("-ss")
        .arg(seek.to_string())
        .arg("-i")
        .arg(source)
        .args(["-frames:v", "1", "-vf", "scale=200:-1", "-q:v", "4"])
        .arg(temporary)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    Ok(status.success() && fs::metadata(temporary).is_ok_and(|metadata| metadata.len() > 0))
}

fn generate_thumbnail(source: &Path, cache: &Path, destination: &Path) -> io::Result<()> {
    let temporary = unique_temp_path(cache);
    let result = (|| {
        if !run_ffmpeg(source, &temporary, 1)? && !run_ffmpeg(source, &temporary, 0)? {
            return Err(io::Error::other("ffmpeg could not extract a frame"));
        }
        fs::rename(&temporary, destination)
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

fn prune_cache(cache: &Path, keep: &HashSet<OsString>) -> io::Result<()> {
    for entry in fs::read_dir(cache)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_file()
            && entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "jpg")
            && !keep.contains(&entry.file_name())
        {
            fs::remove_file(entry.path())?;
        }
    }
    Ok(())
}

fn collect_sources(recording_dir: &Path) -> io::Result<Vec<PathBuf>> {
    let mut sources = Vec::new();
    for entry in fs::read_dir(recording_dir)? {
        let entry = entry?;
        if entry.file_type()?.is_file() && is_recording(&entry.path()) {
            sources.push(entry.path());
        }
    }
    sources.sort();
    Ok(sources)
}

pub(crate) fn recording_thumbnails(recording_dir: Option<&Path>) -> io::Result<()> {
    let Some(recording_dir) = recording_dir.filter(|path| path.is_dir()) else {
        return Ok(());
    };
    let cache = cache_dir().join("silhouette/rec-thumbs");
    prepare_cache(&cache, false)?;
    let _lock = lock_cache(&cache, ".rec-thumbs.lock")?;

    let sources = collect_sources(recording_dir)?;
    let mut keep = HashSet::with_capacity(sources.len());
    let mut work = VecDeque::new();
    for source in sources {
        let Some(name) = output_name(&source) else {
            continue;
        };
        let thumbnail = cache.join(&name);
        keep.insert(name);
        if needs_update(&source, &thumbnail) {
            work.push_back((source, thumbnail));
        }
    }

    prune_cache(&cache, &keep)?;

    if work.is_empty() {
        return Ok(());
    }

    let workers = thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .clamp(1, 4)
        .min(work.len());
    let work = Arc::new(Mutex::new(work));
    let failures = Arc::new(Mutex::new(Vec::new()));

    thread::scope(|scope| {
        for _ in 0..workers {
            let work = Arc::clone(&work);
            let failures = Arc::clone(&failures);
            let cache = &cache;
            scope.spawn(move || loop {
                let task = match work.lock() {
                    Ok(mut queue) => queue.pop_front(),
                    Err(_) => {
                        if let Ok(mut failures) = failures.lock() {
                            failures.push("thumbnail work queue was poisoned".to_owned());
                        }
                        break;
                    }
                };
                let Some((source, destination)) = task else {
                    break;
                };
                if let Err(error) = generate_thumbnail(&source, cache, &destination) {
                    if let Ok(mut failures) = failures.lock() {
                        failures.push(format!("{}: {error}", source.display()));
                    }
                }
            });
        }
    });

    let failures = failures
        .lock()
        .map_err(|_| io::Error::other("thumbnail worker state was poisoned"))?;
    if failures.is_empty() {
        Ok(())
    } else {
        Err(io::Error::other(format!(
            "failed to generate recording thumbnails: {}",
            failures.join("; ")
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_directory() -> PathBuf {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "silhouette-rec-thumb-test-{}-{timestamp}",
            std::process::id()
        ));
        fs::create_dir_all(&directory).unwrap();
        directory
    }

    #[test]
    fn only_recording_mp4_files_are_selected() {
        assert!(is_recording(Path::new("recording_2026-01-02.mp4")));
        assert!(!is_recording(Path::new("movie.mp4")));
        assert!(!is_recording(Path::new("recording_old.MP4")));
        assert!(!is_recording(Path::new("recording_1.mp4.tmp")));
    }

    #[test]
    fn thumbnail_names_keep_the_recording_stem() {
        assert_eq!(
            output_name(Path::new("recording_1.mp4")),
            Some(OsString::from("recording_1.jpg"))
        );
        assert_eq!(output_name(Path::new("recording_1.MP4")), None);
    }

    #[test]
    fn missing_or_empty_thumbnails_need_regeneration() {
        let directory = test_directory();
        let source = directory.join("recording_1.mp4");
        let thumbnail = directory.join("recording_1.jpg");
        fs::write(&source, b"source").unwrap();
        assert!(needs_update(&source, &thumbnail));
        fs::write(&thumbnail, b"").unwrap();
        assert!(needs_update(&source, &thumbnail));
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn thumbnail_is_current_when_source_is_not_newer() {
        let directory = test_directory();
        let source = directory.join("recording_1.mp4");
        let thumbnail = directory.join("recording_1.jpg");
        fs::write(&source, b"source").unwrap();
        thread::sleep(std::time::Duration::from_millis(10));
        fs::write(&thumbnail, b"image").unwrap();
        assert!(!needs_update(&source, &thumbnail));
        fs::remove_dir_all(directory).unwrap();
    }
}
