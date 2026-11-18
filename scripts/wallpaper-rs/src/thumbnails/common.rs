use fs2::FileExt;
use std::{
    fs,
    fs::{File, OpenOptions},
    io::{self, Cursor, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

const MAX_IMAGE_ALLOC: u64 = 256 * 1024 * 1024;
const MAX_IMAGE_EDGE: u32 = 16_384;

fn image_reader_limits() -> image::Limits {
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_EDGE);
    limits.max_image_height = Some(MAX_IMAGE_EDGE);
    limits.max_alloc = Some(MAX_IMAGE_ALLOC);
    limits
}

pub(super) fn decode_image_bytes(bytes: &[u8]) -> image::ImageResult<image::DynamicImage> {
    let mut reader = image::ImageReader::new(Cursor::new(bytes)).with_guessed_format()?;
    reader.limits(image_reader_limits());
    reader.decode()
}

pub(super) fn decode_image_file(path: &Path) -> image::ImageResult<image::DynamicImage> {
    let mut reader = image::ImageReader::open(path)?.with_guessed_format()?;
    reader.limits(image_reader_limits());
    reader.decode()
}

pub(super) fn thumbnail_png(
    image: &image::DynamicImage,
    max_width: u32,
    max_height: u32,
) -> image::ImageResult<Vec<u8>> {
    let thumbnail = image.thumbnail(max_width, max_height);
    let mut output = Cursor::new(Vec::new());
    thumbnail.write_to(&mut output, image::ImageFormat::Png)?;
    Ok(output.into_inner())
}

static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

fn unique_temp_path(cache: &Path, prefix: &str) -> PathBuf {
    let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    cache.join(format!(".{prefix}.{}.{}.tmp", std::process::id(), sequence))
}

pub(super) fn atomic_write_bytes(
    cache: &Path,
    destination: &Path,
    prefix: &str,
    bytes: &[u8],
) -> io::Result<()> {
    for _ in 0..32 {
        let temporary = unique_temp_path(cache, prefix);
        let mut file = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
        {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        };
        let write_result = (|| {
            file.write_all(bytes)?;
            file.flush()?;
            Ok(())
        })();
        drop(file);
        if let Err(error) = write_result {
            let _ = fs::remove_file(&temporary);
            return Err(error);
        }
        if let Err(error) = fs::rename(&temporary, destination) {
            let _ = fs::remove_file(&temporary);
            return Err(error);
        }
        return Ok(());
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "could not allocate a unique thumbnail temporary file",
    ))
}

pub(super) fn prepare_cache(cache: &Path, private: bool) -> io::Result<()> {
    fs::create_dir_all(cache)?;
    let metadata = fs::symlink_metadata(cache)?;
    if !metadata.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "thumbnail cache is not a directory",
        ));
    }
    #[cfg(unix)]
    if private {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(cache, fs::Permissions::from_mode(0o700))?;
    }
    #[cfg(not(unix))]
    let _ = private;
    Ok(())
}

pub(super) fn lock_cache(cache: &Path, name: &str) -> io::Result<File> {
    let path = cache.join(name);
    if fs::symlink_metadata(&path).is_ok_and(|metadata| metadata.file_type().is_symlink()) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "thumbnail cache lock must not be a symlink",
        ));
    }
    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(path)?;
    file.lock_exclusive()?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thumbnail_encoding_bounds_dimensions_and_keeps_aspect_ratio() {
        let image = image::DynamicImage::new_rgb8(1024, 512);
        let bytes = thumbnail_png(&image, 512, 512).unwrap();
        let thumbnail = decode_image_bytes(&bytes).unwrap();
        assert_eq!((thumbnail.width(), thumbnail.height()), (512, 256));
    }
}
