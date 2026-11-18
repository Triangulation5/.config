use super::files::walk_files;
use std::{
    fs,
    path::{Path, PathBuf},
};

const RASTER_SIZES: [&str; 7] = [
    "1024x1024",
    "512x512",
    "256x256",
    "128x128",
    "96x96",
    "64x64",
    "48x48",
];

pub(super) fn install_icon(
    root: &Path,
    icon_name: &str,
    icon_dir: &Path,
    slug: &str,
) -> Result<Option<PathBuf>, String> {
    let files = walk_files(root)
        .map_err(|error| format!("cannot scan app icons in {}: {error}", root.display()))?;
    let icon_name = icon_name
        .rsplit('/')
        .next()
        .unwrap_or(icon_name)
        .rsplit_once('.')
        .map(|(stem, _)| stem)
        .unwrap_or(icon_name);

    let mut found: Option<PathBuf> = None;
    if !icon_name.is_empty() {
        found = files
            .iter()
            .find(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name == format!("{icon_name}.svg"))
                    && path
                        .components()
                        .any(|component| component.as_os_str() == "scalable")
            })
            .cloned();
        if found.is_none() {
            for size in RASTER_SIZES {
                found = files
                    .iter()
                    .find(|path| {
                        path.file_name()
                            .and_then(|name| name.to_str())
                            .is_some_and(|name| name == format!("{icon_name}.png"))
                            && path
                                .components()
                                .any(|component| component.as_os_str() == size)
                    })
                    .cloned();
                if found.is_some() {
                    break;
                }
            }
        }
        if found.is_none() {
            found = files
                .iter()
                .find(|path| {
                    path.file_name()
                        .and_then(|name| name.to_str())
                        .is_some_and(|name| {
                            name == format!("{icon_name}.svg") || name == format!("{icon_name}.png")
                        })
                })
                .cloned();
        }
    }

    if found.is_none() {
        let dir_icon = root.join(".DirIcon");
        if let (Ok(root), Ok(path)) = (root.canonicalize(), dir_icon.canonicalize()) {
            if path.starts_with(root) && path.is_file() {
                found = Some(path);
            }
        }
    }
    if found.is_none() {
        found = files
            .iter()
            .find(|path| {
                path.parent() == Some(root)
                    && path
                        .extension()
                        .and_then(|extension| extension.to_str())
                        .is_some_and(|extension| matches!(extension, "png" | "svg"))
            })
            .cloned();
    }

    let Some(found) = found else {
        return Ok(None);
    };
    let extension = found
        .extension()
        .and_then(|value| value.to_str())
        .filter(|extension| matches!(*extension, "svg" | "png"))
        .ok_or_else(|| format!("unsupported icon type: {}", found.display()))?;
    let destination = icon_dir.join(format!("{slug}.{extension}"));
    fs::copy(&found, &destination).map_err(|error| {
        format!(
            "cannot copy icon {} to {}: {error}",
            found.display(),
            destination.display()
        )
    })?;
    Ok(Some(destination))
}
