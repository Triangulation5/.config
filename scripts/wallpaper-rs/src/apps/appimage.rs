use super::{
    desktop::{
        find_desktop_file, parse_desktop, replace_desktop_line, update_desktop_database,
        write_entry,
    },
    files::{make_executable, TempDir},
    icons::install_icon,
    registry::{AppPaths, AppRecord},
    slug::{channelless, prettify, slugify},
};
use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

pub(super) fn appimage_install(operation: &str, args: &[std::ffi::OsString]) -> Result<(), String> {
    match operation {
        "install" => {
            let (slug, name, action) =
                install_appimage(required_path(args, 0, "install <path-to.AppImage>")?)?;
            println!("{slug}\t{name}\t{action}");
            Ok(())
        }
        "remove" => remove_appimage(required_text(args, 0, "remove <slug>")?),
        "rename" => rename_appimage(
            required_text(args, 0, "rename <slug> <new name>")?,
            required_text(args, 1, "rename <slug> <new name>")?,
        ),
        "heal" => heal_appimage(required_path(args, 0, "heal <missing-AppImage>")?),
        _ => Err("usage: appimage-install.sh install|remove|rename|heal ...".to_owned()),
    }
}

pub(super) fn install_for_launcher(source: &Path) -> Result<(), String> {
    let (_, name, action) = install_appimage(source)?;
    println!("app\t{name}\t{action}");
    Ok(())
}

fn required_text<'a>(
    args: &'a [std::ffi::OsString],
    index: usize,
    usage: &str,
) -> Result<&'a str, String> {
    args.get(index)
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("usage: appimage-install.sh {usage}"))
}

fn required_path<'a>(
    args: &'a [std::ffi::OsString],
    index: usize,
    usage: &str,
) -> Result<&'a Path, String> {
    args.get(index)
        .filter(|value| !value.is_empty())
        .map(Path::new)
        .ok_or_else(|| format!("usage: appimage-install.sh {usage}"))
}

fn install_appimage(source: &Path) -> Result<(String, String, &'static str), String> {
    if !is_appimage(source) {
        return Err(format!("not an AppImage: {}", source.display()));
    }
    let paths = AppPaths::new()?;
    let filename = source
        .file_name()
        .ok_or_else(|| format!("invalid AppImage path: {}", source.display()))?;
    let destination = paths.apps_dir.join(filename);
    if !same_file(source, &destination) {
        fs::copy(source, &destination).map_err(|error| {
            format!(
                "cannot copy {} to {}: {error}",
                source.display(),
                destination.display()
            )
        })?;
    }
    make_executable(&destination)
        .map_err(|error| format!("cannot make {} executable: {error}", destination.display()))?;

    let temp = TempDir::new("silhouette-appimage")
        .map_err(|error| format!("cannot create extraction directory: {error}"))?;
    let extracted = Command::new(&destination)
        .arg("--appimage-extract")
        .current_dir(temp.path())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .and_then(|mut child| {
            let deadline = Instant::now() + Duration::from_secs(60);
            loop {
                match child.try_wait()? {
                    Some(status) => return Ok(status.success()),
                    None if Instant::now() >= deadline => {
                        let _ = child.kill();
                        let _ = child.wait();
                        return Ok(false);
                    }
                    None => thread::sleep(Duration::from_millis(100)),
                }
            }
        })
        .unwrap_or(false)
        && temp.path().join("squashfs-root").is_dir();
    let root = extracted.then(|| temp.path().join("squashfs-root"));

    let mut name = String::new();
    let mut icon_name = String::new();
    let mut categories = String::new();
    let mut wmclass = String::new();
    if let Some(root) = root.as_deref() {
        let desktop = find_desktop_file(root, 2)
            .map_err(|error| format!("cannot scan extracted AppImage: {error}"))?;
        if let Some(desktop) = desktop {
            if let Ok(info) = parse_desktop(&desktop) {
                name = info.name;
                icon_name = info.icon;
                categories = info.categories;
                wmclass = info.wmclass;
            }
        }
    }

    let name = if name.is_empty() {
        prettify(&filename.to_string_lossy())
    } else {
        name
    };
    let mut slug = slugify(&filename.to_string_lossy());
    let app_id = if wmclass.is_empty() {
        name.clone()
    } else {
        wmclass.clone()
    };
    let mut registry = paths.read()?;
    let previous = registry.get(&slug).cloned().unwrap_or_default();
    let (action, obsolete_path) = if previous.appimage_path.is_empty() {
        ("new", None)
    } else if same_file(Path::new(&previous.appimage_path), &destination)
        || previous.appimage_path == destination.to_string_lossy()
    {
        ("reinstalled", None)
    } else if previous.app_id.is_empty() || previous.app_id == app_id {
        ("updated", Some(previous.appimage_path.clone()))
    } else {
        let mut suffix = 2;
        loop {
            let candidate = format!("{slug}-{suffix}");
            if !registry.contains_key(&candidate) {
                slug = candidate;
                break;
            }
            suffix += 1;
        }
        ("new", None)
    };

    if let Some(root) = root.as_deref() {
        let _ = fs::remove_file(paths.icon_dir.join(format!("{slug}.png")));
        let _ = fs::remove_file(paths.icon_dir.join(format!("{slug}.svg")));
        install_icon(root, &icon_name, &paths.icon_dir, &slug)?;
    }
    let icon_path = existing_icon(&paths, &slug);
    let icon_value = icon_path
        .as_ref()
        .map(|path| path.to_string_lossy())
        .unwrap_or_default();
    let desktop = paths.desktop_dir.join(format!("silhouette-{slug}.desktop"));
    let legacy = paths.desktop_dir.join(format!("ricelin-{slug}.desktop"));
    let _ = fs::remove_file(legacy);
    write_entry(
        &desktop,
        &destination,
        &name,
        icon_value.as_ref(),
        &categories,
        &wmclass,
    )
    .map_err(|error| format!("cannot write {}: {error}", desktop.display()))?;
    registry.insert(
        slug.clone(),
        AppRecord {
            name: name.clone(),
            appimage_path: destination.to_string_lossy().into_owned(),
            icon_path: icon_path.unwrap_or_default().to_string_lossy().into_owned(),
            desktop_path: desktop.to_string_lossy().into_owned(),
            app_id,
        },
    );
    paths.write(&registry)?;
    if let Some(obsolete_path) = obsolete_path {
        remove_previous_app(&paths, &obsolete_path);
    }
    Ok((slug, name, action))
}

fn is_appimage(path: &Path) -> bool {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default();
    if !extension.eq_ignore_ascii_case("appimage") || !path.is_file() {
        return false;
    }
    let Ok(mut file) = fs::File::open(path) else {
        return false;
    };
    let mut magic = [0; 4];
    file.read_exact(&mut magic).is_ok() && magic == *b"\x7fELF"
}

fn same_file(left: &Path, right: &Path) -> bool {
    match (left.canonicalize(), right.canonicalize()) {
        (Ok(left), Ok(right)) => left == right,
        _ => left == right,
    }
}

fn existing_icon(paths: &AppPaths, slug: &str) -> Option<PathBuf> {
    ["png", "svg"]
        .into_iter()
        .map(|extension| paths.icon_dir.join(format!("{slug}.{extension}")))
        .find(|path| path.is_file())
}

fn remove_previous_app(paths: &AppPaths, raw_path: &str) {
    if raw_path.is_empty() {
        return;
    }
    let path = Path::new(raw_path);
    if !paths.owns_path(&paths.apps_dir, path) {
        return;
    }
    if path.is_dir() {
        let _ = fs::remove_dir_all(path);
    } else {
        let _ = fs::remove_file(path);
    }
}

fn remove_appimage(slug: &str) -> Result<(), String> {
    let paths = AppPaths::new()?;
    let mut registry = paths.read()?;
    if let Some(record) = registry.remove(slug) {
        remove_previous_app(&paths, &record.appimage_path);
        remove_owned_file(&paths, &paths.icon_dir, &record.icon_path);
        remove_owned_file(&paths, &paths.desktop_dir, &record.desktop_path);
        update_desktop_database(Some(&paths.desktop_dir));
    }
    paths.write(&registry)
}

fn remove_owned_file(paths: &AppPaths, directory: &Path, raw_path: &str) {
    if raw_path.is_empty() {
        return;
    }
    let path = Path::new(raw_path);
    if paths.owns_path(directory, path) {
        let _ = fs::remove_file(path);
    }
}

fn rename_appimage(slug: &str, name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("usage: appimage-install.sh rename <slug> <new name>".to_owned());
    }
    let paths = AppPaths::new()?;
    let mut registry = paths.read()?;
    let record = registry
        .get_mut(slug)
        .ok_or_else(|| format!("unknown slug: {slug}"))?;
    let desktop = Path::new(&record.desktop_path);
    if !paths.owns_path(&paths.desktop_dir, desktop) || !desktop.is_file() {
        return Err(format!("desktop entry missing: {}", desktop.display()));
    }
    replace_desktop_line(desktop, "Name", name)
        .map_err(|error| format!("cannot update {}: {error}", desktop.display()))?;
    record.name = name.to_owned();
    paths.write(&registry)
}

fn heal_appimage(missing: &Path) -> Result<(), String> {
    let paths = AppPaths::new()?;
    let filename = missing
        .file_name()
        .ok_or_else(|| format!("invalid AppImage path: {}", missing.display()))?
        .to_string_lossy();
    let slug = slugify(&filename);
    let loose_slug = channelless(&slug);
    let mut newest: Option<(PathBuf, std::time::SystemTime)> = None;
    let mut fallback: Option<(PathBuf, std::time::SystemTime)> = None;
    for entry in fs::read_dir(&paths.apps_dir)
        .map_err(|error| format!("cannot scan {}: {error}", paths.apps_dir.display()))?
    {
        let entry = entry.map_err(|error| format!("cannot read AppImage directory: {error}"))?;
        if !entry
            .file_type()
            .map_err(|error| error.to_string())?
            .is_file()
            || !entry
                .path()
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| extension.eq_ignore_ascii_case("appimage"))
        {
            continue;
        }
        let file_path = entry.path();
        let file_slug = slugify(&entry.file_name().to_string_lossy());
        let modified = entry
            .metadata()
            .and_then(|metadata| metadata.modified())
            .unwrap_or(std::time::UNIX_EPOCH);
        if file_slug == slug {
            let is_newer = match newest.as_ref() {
                Some((_, time)) => modified > *time,
                None => true,
            };
            if is_newer {
                newest = Some((file_path, modified));
            }
        } else if !loose_slug.is_empty()
            && channelless(&file_slug) == loose_slug
            && match fallback.as_ref() {
                Some((_, time)) => modified > *time,
                None => true,
            }
        {
            fallback = Some((file_path, modified));
        }
    }
    let replacement = newest
        .or(fallback)
        .map(|(path, _)| path)
        .ok_or_else(|| format!("no replacement for {}", missing.display()))?;

    let mut registry = paths.read()?;
    let key = registry
        .iter()
        .find(|(_, record)| record.appimage_path == missing.to_string_lossy())
        .map(|(key, _)| key.clone())
        .ok_or_else(|| format!("unregistered AppImage: {}", missing.display()))?;
    let record = registry
        .get_mut(&key)
        .ok_or_else(|| format!("unregistered AppImage: {}", missing.display()))?;
    let desktop = Path::new(&record.desktop_path);
    if !paths.owns_path(&paths.desktop_dir, desktop) || !desktop.is_file() {
        return Err(format!("desktop entry missing: {}", desktop.display()));
    }
    replace_desktop_line(
        desktop,
        "Exec",
        &format!("\"{}\" %U", replacement.to_string_lossy()),
    )
    .map_err(|error| format!("cannot update {}: {error}", desktop.display()))?;
    record.appimage_path = replacement.to_string_lossy().into_owned();
    paths.write(&registry)?;
    println!("{}", replacement.display());
    Ok(())
}
