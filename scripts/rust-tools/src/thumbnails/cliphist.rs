use super::common::{
    atomic_write_bytes, decode_image_bytes, lock_cache, prepare_cache, thumbnail_png,
};
use crate::config::cache_dir;
use std::{
    collections::HashSet,
    fs,
    io::{self, Read, Write},
    path::Path,
    process::{Command, Stdio},
};

const MAX_CLIPHIST_IMAGE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_CLIPHIST_LIST_BYTES: u64 = 64 * 1024 * 1024;

fn is_clipboard_image_entry(description: &str) -> bool {
    let lower = description.to_ascii_lowercase();
    lower.contains("[[ binary data")
        && ["png", "jpg", "jpeg", "gif", "bmp", "webp"]
            .iter()
            .any(|format| {
                lower
                    .split(|character: char| !character.is_ascii_alphanumeric())
                    .any(|word| word == *format)
            })
}

fn cliphist_id(value: &str) -> bool {
    !value.is_empty() && value.len() <= 20 && value.bytes().all(|byte| byte.is_ascii_digit())
}

fn decode_cliphist_entry(id: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let mut child = Command::new("cliphist")
        .arg("decode")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        if let Err(error) = stdin.write_all(id.as_bytes()) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error.into());
        }
    }
    let Some(stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return Err(
            io::Error::new(io::ErrorKind::BrokenPipe, "cliphist decode has no stdout").into(),
        );
    };
    let mut limited = stdout.take(MAX_CLIPHIST_IMAGE_BYTES + 1);
    let mut bytes = Vec::new();
    if let Err(error) = limited.read_to_end(&mut bytes) {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error.into());
    }
    if bytes.len() as u64 > MAX_CLIPHIST_IMAGE_BYTES {
        let _ = child.kill();
        let _ = child.wait();
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "clipboard image exceeds the 64 MiB input limit",
        )
        .into());
    }
    if !child.wait()?.success() {
        return Err(io::Error::other("cliphist decode failed").into());
    }
    Ok(bytes)
}

fn cliphist_list() -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let mut child = Command::new("cliphist")
        .arg("list")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let Some(stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return Err(
            io::Error::new(io::ErrorKind::BrokenPipe, "cliphist list has no stdout").into(),
        );
    };
    let mut limited = stdout.take(MAX_CLIPHIST_LIST_BYTES + 1);
    let mut bytes = Vec::new();
    if let Err(error) = limited.read_to_end(&mut bytes) {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error.into());
    }
    if bytes.len() as u64 > MAX_CLIPHIST_LIST_BYTES {
        let _ = child.kill();
        let _ = child.wait();
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "cliphist list exceeds the 64 MiB input limit",
        )
        .into());
    }
    if !child.wait()?.success() {
        return Err(io::Error::other("cliphist list failed").into());
    }
    Ok(bytes)
}

fn prune_cliphist_cache(cache: &Path, active_ids: &HashSet<String>) -> io::Result<()> {
    let entries = fs::read_dir(cache)?.collect::<Result<Vec<_>, _>>()?;
    for entry in entries {
        let path = entry.path();
        if !entry.file_type()?.is_file() || !path.extension().is_some_and(|ext| ext == "png") {
            continue;
        }
        let Some(id) = path.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        if cliphist_id(id) && !active_ids.contains(id) {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

pub(crate) fn cliphist_thumbnails() -> Result<(), Box<dyn std::error::Error>> {
    let cache = cache_dir().join("cliphist-thumbs");
    prepare_cache(&cache, true)?;
    let _lock = lock_cache(&cache, ".cliphist-thumbs.lock")?;
    let output = cliphist_list()?;
    let mut active_ids = HashSet::new();
    let mut image_ids = Vec::new();
    for line in String::from_utf8_lossy(&output).lines() {
        let Some((id, description)) = line.split_once('\t') else {
            continue;
        };
        if !cliphist_id(id) {
            continue;
        }
        active_ids.insert(id.to_string());
        if is_clipboard_image_entry(description) {
            image_ids.push(id.to_string());
        }
    }
    prune_cliphist_cache(&cache, &active_ids)?;

    for id in image_ids {
        let destination = cache.join(format!("{id}.png"));
        if fs::symlink_metadata(&destination)
            .is_ok_and(|metadata| metadata.file_type().is_file() && metadata.len() > 0)
        {
            continue;
        }
        let result = decode_cliphist_entry(&id)
            .and_then(|bytes| decode_image_bytes(&bytes).map_err(Into::into))
            .and_then(|image| thumbnail_png(&image, 256, 256).map_err(Into::into));
        match result {
            Ok(bytes) => {
                if let Err(error) =
                    atomic_write_bytes(&cache, &destination, "cliphist-thumb", &bytes)
                {
                    eprintln!("cliphist-thumbs: cannot write {destination:?}: {error}");
                }
            }
            Err(error) => eprintln!("cliphist-thumbs: skipping entry {id}: {error}"),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clipboard_metadata_and_ids_are_filtered_safely() {
        assert!(is_clipboard_image_entry(
            "[[ binary data image/png 640x480 ]]"
        ));
        assert!(is_clipboard_image_entry(
            "[[ binary data image/webp 640x480 ]]"
        ));
        assert!(!is_clipboard_image_entry("[[ binary data text/plain ]]"));
        assert!(cliphist_id("12345"));
        assert!(!cliphist_id("../12345"));
    }
}
