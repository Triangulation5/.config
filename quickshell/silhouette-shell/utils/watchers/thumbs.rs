use std::collections::HashSet;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::UNIX_EPOCH;

pub(crate) fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                use std::fmt::Write as _;
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn worker_count(task_len: usize) -> usize {
    let cpus = thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4);
    cpus.min(8).min(task_len.max(1))
}

fn find_magick_bin() -> Option<&'static str> {
    ["magick", "convert"].into_iter().find(|&bin| {
        Command::new(bin)
            .arg("-version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    })
}

fn prune_stale_thumbs(thumb_dir: &Path, ext: &str, expected: &HashSet<String>) {
    if let Ok(entries) = fs::read_dir(thumb_dir) {
        for entry in entries.flatten() {
            let fname = entry.file_name().to_string_lossy().into_owned();
            if fname.ends_with(ext) && !expected.contains(&fname) {
                let _ = fs::remove_file(entry.path());
            }
        }
    }
}

fn ensure_trailing_slash(s: &str) -> String {
    if s.ends_with('/') {
        s.to_string()
    } else {
        format!("{}/", s)
    }
}

fn run_parallel_jobs<T: Sync, F: Fn(&T) + Sync>(jobs: &[T], work: F) {
    if jobs.is_empty() {
        return;
    }
    let next_idx = AtomicUsize::new(0);
    let n_workers = worker_count(jobs.len());
    thread::scope(|s| {
        for _ in 0..n_workers {
            s.spawn(|| loop {
                let idx = next_idx.fetch_add(1, Ordering::Relaxed);
                if idx >= jobs.len() {
                    break;
                }
                work(&jobs[idx]);
            });
        }
    });
}

fn walk_wallpapers(dir: &Path, out: &mut Vec<(f64, PathBuf, String)>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let ft = match entry.file_type() {
            Ok(t) => t,
            Err(_) => continue,
        };
        if ft.is_dir() {
            walk_wallpapers(&path, out);
        } else if ft.is_file() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let lower = name.to_ascii_lowercase();
            if lower.ends_with(".jpg") || lower.ends_with(".jpeg") || lower.ends_with(".png") {
                let mtime = entry
                    .metadata()
                    .ok()
                    .and_then(|m| m.modified().ok())
                    .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                    .map(|d| d.as_secs_f64())
                    .unwrap_or(0.0);
                out.push((mtime, path, name));
            }
        }
    }
}

/// Parallel wallpaper thumbnailer + directory indexer + state reader.
/// Usage: thumbs-walls <wp_dir> <thumb_dir> <state_file>
pub fn cmd_thumbs_walls(args: &[String]) {
    if args.len() < 3 {
        std::process::exit(2);
    }
    let wp_dir = Path::new(&args[0]);
    let thumb_dir = Path::new(&args[1]);
    let state_file = Path::new(&args[2]);
    let _ = fs::create_dir_all(thumb_dir);

    let mut files: Vec<(f64, PathBuf, String)> = Vec::new();
    if wp_dir.is_dir() {
        walk_wallpapers(wp_dir, &mut files);
    }
    files.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));

    let mut expected: HashSet<String> = HashSet::with_capacity(files.len());
    let mut jobs: Vec<(PathBuf, PathBuf)> = Vec::new();
    for (src_mtime, src_path, name) in &files {
        let thumb_name = format!("{}.png", name);
        expected.insert(thumb_name.clone());
        let dst = thumb_dir.join(&thumb_name);
        let need = match fs::metadata(&dst).and_then(|m| m.modified()) {
            Ok(dst_t) => {
                let dst_secs = dst_t
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_secs_f64())
                    .unwrap_or(0.0);
                dst_secs < *src_mtime
            }
            Err(_) => true,
        };
        if need {
            jobs.push((src_path.clone(), dst));
        }
    }

    prune_stale_thumbs(thumb_dir, ".png", &expected);

    if let Some(magick) = find_magick_bin() {
        run_parallel_jobs(&jobs, |(src, dst)| {
            let tmp = dst.with_extension("png.tmp");
            let ok = Command::new(magick)
                .arg(src)
                .args(["-thumbnail", "512x512>", "-strip"])
                .arg(format!("png:{}", tmp.display()))
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|st| st.success())
                .unwrap_or(false);
            if ok {
                let _ = fs::rename(&tmp, dst);
            } else {
                let _ = fs::remove_file(&tmp);
            }
        });
    }

    let current = fs::read_to_string(state_file)
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    let thumb_prefix = ensure_trailing_slash(&args[1]);

    let stdout = io::stdout();
    let mut out = stdout.lock();
    let _ = write!(out, "{{\"current\":{},\"entries\":[", json_escape(&current));
    for (i, (mtime, path, name)) in files.iter().enumerate() {
        if i > 0 {
            let _ = write!(out, ",");
        }
        let thumb = format!("{}{}.png", thumb_prefix, name);
        let _ = write!(
            out,
            "{{\"path\":{},\"name\":{},\"mtime\":{:.3},\"thumb\":{}}}",
            json_escape(&path.to_string_lossy()),
            json_escape(name),
            mtime,
            json_escape(&thumb)
        );
    }
    let _ = writeln!(out, "]}}");
    let _ = out.flush();
}

struct ClipEntry {
    id: String,
    preview: String,
    is_image: bool,
    label: String,
    size_label: String,
}

fn parse_binary_meta(preview: &str) -> Option<(String, String)> {
    let inner = preview
        .strip_prefix("[[ binary data ")?
        .strip_suffix(" ]]")?;
    let tokens: Vec<&str> = inner.split_whitespace().collect();
    let is_img = tokens
        .iter()
        .any(|t| matches!(*t, "png" | "jpg" | "jpeg" | "gif" | "bmp" | "webp"));
    if !is_img {
        return None;
    }
    if tokens.len() == 4 {
        if let Some((w, h)) = tokens[3].split_once('x') {
            if !w.is_empty()
                && !h.is_empty()
                && w.bytes().all(|b| b.is_ascii_digit())
                && h.bytes().all(|b| b.is_ascii_digit())
            {
                let size_label = format!("{} {}", tokens[0], tokens[1]);
                let label = format!("{} {}×{}", tokens[2], w, h);
                return Some((label, size_label));
            }
        }
    }
    Some((inner.to_string(), String::new()))
}

/// Parallel cliphist thumbnailer + list parser.
/// Usage: thumbs-cliphist <thumb_dir>
pub fn cmd_thumbs_cliphist(args: &[String]) {
    if args.is_empty() {
        std::process::exit(2);
    }
    let thumb_dir = Path::new(&args[0]);
    let _ = fs::create_dir_all(thumb_dir);

    let output = match Command::new("cliphist").arg("list").output() {
        Ok(o) => o,
        Err(_) => std::process::exit(1),
    };
    if !output.status.success() {
        std::process::exit(output.status.code().unwrap_or(1));
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut entries: Vec<ClipEntry> = Vec::new();
    let mut expected: HashSet<String> = HashSet::new();
    let mut jobs: Vec<(String, PathBuf)> = Vec::new();

    for line in text.lines() {
        if entries.len() >= 150 {
            break;
        }
        let Some((id, preview)) = line.split_once('\t') else {
            continue;
        };
        if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        if let Some((label, size_label)) = parse_binary_meta(preview) {
            let fname = format!("{}.png", id);
            expected.insert(fname.clone());
            let dst = thumb_dir.join(&fname);
            if !dst.exists() {
                jobs.push((id.to_string(), dst));
            }
            entries.push(ClipEntry {
                id: id.to_string(),
                preview: preview.to_string(),
                is_image: true,
                label,
                size_label,
            });
        } else {
            entries.push(ClipEntry {
                id: id.to_string(),
                preview: preview.to_string(),
                is_image: false,
                label: String::new(),
                size_label: String::new(),
            });
        }
    }

    prune_stale_thumbs(thumb_dir, ".png", &expected);

    if let Some(magick) = find_magick_bin() {
        run_parallel_jobs(&jobs, |(id, dst)| {
            if let Ok(dec) = Command::new("cliphist").args(["decode", id]).output() {
                if dec.status.success() && !dec.stdout.is_empty() {
                    let tmp = dst.with_extension("png.tmp");
                    if let Ok(mut child) = Command::new(magick)
                        .args(["-", "-thumbnail", "320x240>", "-strip"])
                        .arg(format!("png:{}", tmp.display()))
                        .stdin(Stdio::piped())
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn()
                    {
                        if let Some(mut stdin) = child.stdin.take() {
                            let _ = stdin.write_all(&dec.stdout);
                        }
                        if child.wait().map(|st| st.success()).unwrap_or(false) {
                            let _ = fs::rename(&tmp, dst);
                        } else {
                            let _ = fs::remove_file(&tmp);
                        }
                    }
                }
            }
        });
    }

    let thumb_prefix = ensure_trailing_slash(&args[0]);
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let _ = write!(out, "[");
    for (i, e) in entries.iter().enumerate() {
        if i > 0 {
            let _ = write!(out, ",");
        }
        let thumb = if e.is_image {
            format!("{}{}.png", thumb_prefix, e.id)
        } else {
            String::new()
        };
        let _ = write!(
            out,
            "{{\"id\":{},\"preview\":{},\"isImage\":{},\"label\":{},\"sizeLabel\":{},\"thumb\":{}}}",
            json_escape(&e.id),
            json_escape(&e.preview),
            if e.is_image { "true" } else { "false" },
            json_escape(&e.label),
            json_escape(&e.size_label),
            json_escape(&thumb)
        );
    }
    let _ = writeln!(out, "]");
    let _ = out.flush();
}

/// Parallel recording cover-frame thumbnailer + recent list indexer.
/// Usage: thumbs-rec <out_dir> <thumb_dir> <max_count> <cleared_before>
pub fn cmd_thumbs_rec(args: &[String]) {
    if args.len() < 4 {
        std::process::exit(2);
    }
    let out_dir = Path::new(&args[0]);
    let thumb_dir = Path::new(&args[1]);
    let max_count: usize = args[2].parse().unwrap_or(12).max(1);
    let cleared_before: f64 = args[3].parse().unwrap_or(0.0);
    let _ = fs::create_dir_all(thumb_dir);

    let mut clips: Vec<(f64, u64, PathBuf, String)> = Vec::new();
    if let Ok(entries) = fs::read_dir(out_dir) {
        for entry in entries.flatten() {
            if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if !(name.starts_with("recording_") && name.ends_with(".mp4")) {
                continue;
            }
            if let Ok(meta) = entry.metadata() {
                let mtime = meta
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                    .map(|d| d.as_secs_f64())
                    .unwrap_or(0.0);
                if mtime > cleared_before {
                    clips.push((mtime, meta.len(), entry.path(), name));
                }
            }
        }
    }
    clips.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    clips.truncate(max_count);

    let mut expected: HashSet<String> = HashSet::with_capacity(clips.len());
    let mut jobs: Vec<(PathBuf, PathBuf)> = Vec::new();
    for (_, _, src, name) in &clips {
        let stem = name.strip_suffix(".mp4").unwrap_or(name);
        let fname = format!("{}.jpg", stem);
        expected.insert(fname.clone());
        let dst = thumb_dir.join(&fname);
        if !dst.exists() {
            jobs.push((src.clone(), dst));
        }
    }

    prune_stale_thumbs(thumb_dir, ".jpg", &expected);

    run_parallel_jobs(&jobs, |(src, dst)| {
        let tmp = dst.with_extension("jpg.tmp");
        let run_ff = |seek: bool| -> bool {
            let mut cmd = Command::new("ffmpeg");
            cmd.args(["-y", "-loglevel", "error"]);
            if seek {
                cmd.args(["-ss", "00:00:00.5"]);
            }
            cmd.arg("-i")
                .arg(src)
                .args(["-frames:v", "1", "-vf", "scale=480:-1", "-f", "image2"])
                .arg(&tmp)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|st| st.success() && tmp.exists())
                .unwrap_or(false)
        };
        if run_ff(true) || run_ff(false) {
            let _ = fs::rename(&tmp, dst);
        } else {
            let _ = fs::remove_file(&tmp);
        }
    });

    let thumb_prefix = ensure_trailing_slash(&args[1]);
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let _ = write!(out, "[");
    for (i, (mtime, bytes, path, name)) in clips.iter().enumerate() {
        if i > 0 {
            let _ = write!(out, ",");
        }
        let stem = name.strip_suffix(".mp4").unwrap_or(name);
        let thumb = format!("{}{}.jpg", thumb_prefix, stem);
        let _ = write!(
            out,
            "{{\"path\":{},\"name\":{},\"mtime\":{:.3},\"bytes\":{},\"thumb\":{}}}",
            json_escape(&path.to_string_lossy()),
            json_escape(name),
            mtime,
            bytes,
            json_escape(&thumb)
        );
    }
    let _ = writeln!(out, "]");
    let _ = out.flush();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_escape_handles_specials() {
        assert_eq!(json_escape("a\"b\\c\nd\te"), "\"a\\\"b\\\\c\\nd\\te\"");
        assert_eq!(json_escape("\x07"), "\"\\u0007\"");
    }

    #[test]
    fn binary_meta_parses_images_and_rejects_text() {
        assert_eq!(
            parse_binary_meta("[[ binary data 245 KiB png 1920x1080 ]]"),
            Some(("png 1920×1080".to_string(), "245 KiB".to_string()))
        );
        assert_eq!(
            parse_binary_meta("[[ binary data 12 KiB webp 640x480 ]]"),
            Some(("webp 640×480".to_string(), "12 KiB".to_string()))
        );
        assert_eq!(parse_binary_meta("[[ binary data 4 KiB pdf ]]"), None);
        assert_eq!(parse_binary_meta("plain text entry"), None);
    }
}
