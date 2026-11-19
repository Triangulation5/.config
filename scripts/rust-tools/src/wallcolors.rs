use crate::config::{flags, home};
use serde_json::{json, Map, Value};
use sha1::{Digest, Sha1};
use std::{
    cmp::Ordering,
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
    process::Command,
    time::UNIX_EPOCH,
};

const SCHEMES: &[&str] = &[
    "tonal-spot",
    "vibrant",
    "expressive",
    "fidelity",
    "content",
    "fruit-salad",
    "rainbow",
    "neutral",
    "monochrome",
];
const PREFERS: &[&str] = &[
    "saturation",
    "less-saturation",
    "lightness",
    "darkness",
    "value",
];
const SURF_NAMES: [&str; 6] = [
    "surface",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "outline_variant",
];
const DARK_STEPS: [f64; 6] = [0.0, 0.022, 0.038, 0.065, 0.1, 0.225];
const LIGHT_STEPS: [f64; 6] = [0.0, -0.045, -0.075, -0.115, -0.16, -0.34];
const TEXT_KEYS: [&str; 7] = [
    "cream",
    "bright",
    "subtle",
    "dim",
    "faint",
    "icon_dim",
    "tick_rest",
];
const DARK_TEXT: [(f64, f64); 7] = [
    (0.90, 0.05),
    (0.97, 0.03),
    (0.73, 0.07),
    (0.54, 0.06),
    (0.44, 0.05),
    (0.81, 0.07),
    (0.75, 0.08),
];
const LIGHT_TEXT: [(f64, f64); 7] = [
    (0.20, 0.18),
    (0.10, 0.20),
    (0.36, 0.14),
    (0.48, 0.10),
    (0.56, 0.08),
    (0.28, 0.12),
    (0.34, 0.12),
];
const CONTAINER_KEYS: [&str; 7] = [
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "primary_container",
    "secondary_container",
    "tertiary_container",
];
const TERMINAL_ANSI: [&str; 16] = [
    "00", "08", "0b", "0a", "0d", "0e", "0c", "05", "03", "08", "0b", "0a", "0d", "0e", "0c", "07",
];

type Rgb = (f64, f64, f64);
type MaterialColors = BTreeMap<String, String>;

pub(crate) fn run(args: &[std::ffi::OsString]) -> bool {
    let args = args
        .iter()
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    if let Err(error) = generate(&args) {
        eprintln!("wallcolors: {error}");
        return false;
    }
    true
}

fn generate(args: &[String]) -> Result<(), String> {
    if args.is_empty() {
        return Err("usage: wallcolors.py [--hue HUE [MODE [SATURATION]] | WALLPAPER]".to_owned());
    }

    let cache = home().join(".cache/silhouette");
    let (pill, source_hex) = if args[0] == "--hue" {
        let hue = parse_arg(args.get(1), "hue")?.rem_euclid(360.0) / 360.0;
        let mode = args.get(2).map(String::as_str).unwrap_or("dark");
        let saturation = args
            .get(3)
            .map(|value| parse_float(value, "saturation"))
            .transpose()?
            .unwrap_or(0.5)
            .clamp(0.0, 1.0);
        let mean_lightness = if mode == "light" { 0.85 } else { 0.12 };
        let pill = hsl_palette(hue, saturation, mean_lightness);
        let source = if saturation > 0.02 {
            tint(hue, saturation, 0.45)
        } else {
            "#787878".to_owned()
        };
        (pill, source)
    } else {
        let wallpaper = PathBuf::from(&args[0]);
        if !wallpaper.is_file() {
            return Ok(());
        }
        let mut settings = flags().as_object().cloned().unwrap_or_else(Map::new);
        if setting_string(&settings, "paletteMode") == Some("accented") {
            settings.insert("dynamicMode".to_owned(), json!("dark"));
            settings.insert("surfaceRole".to_owned(), json!("default"));
        }

        let image = wallpaper_thumbnail(&wallpaper, &cache);
        if setting_string(&settings, "dynamicScheme") == Some("auto") {
            let (_, variant) = smart_mode_variant(&image);
            settings.insert("dynamicScheme".to_owned(), json!(variant));
        }

        match matugen_image(&image, &settings)
            .and_then(|colors| material_palette(&colors, &settings).map(|pill| (colors, pill)))
        {
            Ok((colors, pill)) => {
                let source = colors
                    .get("source_color")
                    .cloned()
                    .or_else(|| palette_color(&pill, "primary").map(str::to_owned))
                    .ok_or_else(|| "matugen did not return a source colour".to_owned())?;
                (pill, source)
            }
            Err(_) => fallback_palette(&wallpaper, &settings)?,
        }
    };

    fs::create_dir_all(&cache)
        .map_err(|error| format!("could not create {}: {error}", cache.display()))?;
    let colors_path = cache.join("colors.json");
    let document = serde_json::to_string_pretty(&Value::Object(pill.clone()))
        .map_err(|error| format!("could not encode colors.json: {error}"))?;
    write_atomic(&colors_path, &(document + "\n"))
        .map_err(|error| format!("could not write {}: {error}", colors_path.display()))?;
    render_fastfetch(&pill)?;

    let Ok(base16) = matugen_terminal(&source_hex) else {
        return Ok(());
    };
    let Some(terminal) = terminal_colors(&base16) else {
        return Ok(());
    };
    let Ok(kitty) = render_kitty(&terminal, &pill) else {
        return Ok(());
    };
    let kitty_path = cache.join("kitty-colors");
    write_atomic(&kitty_path, &kitty)
        .map_err(|error| format!("could not write {}: {error}", kitty_path.display()))?;
    Ok(())
}

fn fallback_palette(
    wallpaper: &Path,
    settings: &Map<String, Value>,
) -> Result<(Map<String, Value>, String), String> {
    let (hue, mut lightness) = analyze(wallpaper);
    let (hue, saturation) = hue.unwrap_or((0.09, 0.0));
    if setting_string(settings, "paletteMode") == Some("accented") {
        lightness = 0.12;
    }
    let pill = hsl_palette(hue, saturation, lightness);
    let source = if saturation > 0.02 {
        tint(hue, saturation, 0.45)
    } else {
        "#787878".to_owned()
    };
    Ok((pill, source))
}

fn parse_arg(value: Option<&String>, name: &str) -> Result<f64, String> {
    let value = value.ok_or_else(|| format!("missing {name}"))?;
    parse_float(value, name)
}

fn parse_float(value: &str, name: &str) -> Result<f64, String> {
    let number = value
        .parse::<f64>()
        .map_err(|_| format!("invalid {name}: {value}"))?;
    if number.is_finite() {
        Ok(number)
    } else {
        Err(format!("invalid {name}: {value}"))
    }
}

fn setting_string<'a>(settings: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    settings.get(key).and_then(Value::as_str)
}

fn analyze(wallpaper: &Path) -> (Option<(f64, f64)>, f64) {
    let output = Command::new("magick")
        .arg(wallpaper)
        .args([
            "-alpha",
            "off",
            "-resize",
            "200x200",
            "-colors",
            "48",
            "-format",
            "%c",
            "histogram:info:-",
        ])
        .output()
        .ok()
        .map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
        .unwrap_or_default();
    analyze_histogram(&output)
}

fn analyze_histogram(output: &str) -> (Option<(f64, f64)>, f64) {
    let mut buckets: [Option<(f64, Option<(f64, f64, f64)>)>; 12] = [None; 12];
    let mut total = 0_u64;
    let mut light_sum = 0.0;
    let mut chroma = 0_u64;
    for line in output.lines() {
        let Some((count, rgb)) = parse_histogram_line(line) else {
            continue;
        };
        let (hue, lightness, saturation) = rgb_to_hls(rgb);
        total += count;
        light_sum += count as f64 * lightness;
        if saturation < 0.15 || lightness < 0.05 || lightness > 0.92 {
            continue;
        }
        chroma += count;
        let bucket_index = ((hue * 360.0) as usize / 30) % 12;
        let bucket = buckets[bucket_index].get_or_insert((0.0, None));
        bucket.0 += count as f64 * saturation;
        let score = count as f64
            * saturation
            * if 0.12 < lightness && lightness < 0.55 {
                1.0
            } else {
                0.4
            };
        if bucket.1.is_none_or(|(best, _, _)| score > best) {
            bucket.1 = Some((score, hue, saturation));
        }
    }
    let mean_lightness = if total > 0 {
        light_sum / total as f64
    } else {
        0.0
    };
    if total == 0 || (chroma as f64) < 0.08 * total as f64 {
        return (None, mean_lightness);
    }
    let winner = buckets.into_iter().flatten().reduce(|best, candidate| {
        if candidate.0 > best.0 {
            candidate
        } else {
            best
        }
    });
    let hue = winner.and_then(|(_, best)| best.map(|(_, hue, saturation)| (hue, saturation)));
    (hue, mean_lightness)
}

fn parse_histogram_line(line: &str) -> Option<(u64, Rgb)> {
    let line = line.trim_start();
    let (count, rest) = line.split_once(':')?;
    let count = count.trim().parse::<u64>().ok()?;
    let hex = rest.split('#').nth(1)?.get(..6)?;
    let parsed = u32::from_str_radix(hex, 16).ok()?;
    Some((
        count,
        (
            ((parsed >> 16) & 0xff) as f64 / 255.0,
            ((parsed >> 8) & 0xff) as f64 / 255.0,
            (parsed & 0xff) as f64 / 255.0,
        ),
    ))
}

fn sample_pixels(image: &Path, size: usize) -> Vec<Rgb> {
    let output = Command::new("magick")
        .arg(image)
        .args([
            "-alpha",
            "off",
            "-resize",
            &format!("{size}x{size}!"),
            "-depth",
            "8",
            "rgb:-",
        ])
        .output();
    let Ok(output) = output else {
        return Vec::new();
    };
    output
        .stdout
        .chunks_exact(3)
        .map(|rgb| {
            (
                rgb[0] as f64 / 255.0,
                rgb[1] as f64 / 255.0,
                rgb[2] as f64 / 255.0,
            )
        })
        .collect()
}

fn wallpaper_thumbnail(wallpaper: &Path, cache: &Path) -> PathBuf {
    let Ok(metadata) = fs::metadata(wallpaper) else {
        return wallpaper.to_path_buf();
    };
    let modified = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos() as i128)
        .unwrap_or_default();
    let key = format!(
        "{}|{}|{}",
        wallpaper.to_string_lossy(),
        modified,
        metadata.len()
    );
    let digest = Sha1::digest(key.as_bytes());
    let key = digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let thumbs = cache.join("thumbs");
    let destination = thumbs.join(format!("{key}.png"));
    if fs::metadata(&destination).is_ok_and(|metadata| metadata.len() > 0) {
        return destination;
    }
    if fs::create_dir_all(&thumbs).is_err() {
        return wallpaper.to_path_buf();
    }
    let made = Command::new("magick")
        .args(["-define", "jpeg:size=256x256"])
        .arg(wallpaper)
        .args(["-alpha", "off", "-resize", "128x128!"])
        .arg(&destination)
        .output();
    if !made.is_ok_and(|output| output.status.success())
        || !fs::metadata(&destination).is_ok_and(|metadata| metadata.len() > 0)
    {
        let _ = fs::remove_file(&destination);
        return wallpaper.to_path_buf();
    }

    if let Ok(entries) = fs::read_dir(&thumbs) {
        let mut cached = entries
            .flatten()
            .filter(|entry| {
                entry
                    .path()
                    .extension()
                    .and_then(|extension| extension.to_str())
                    == Some("png")
                    && entry.path().is_file()
            })
            .map(|entry| {
                let modified = entry
                    .metadata()
                    .and_then(|metadata| metadata.modified())
                    .unwrap_or(UNIX_EPOCH);
                (modified, entry.path())
            })
            .collect::<Vec<_>>();
        cached.sort_by(|left, right| left.0.cmp(&right.0));
        let excess = cached.len().saturating_sub(128);
        for (_, stale) in cached.into_iter().take(excess) {
            let _ = fs::remove_file(stale);
        }
    }
    if fs::metadata(&destination).is_ok_and(|metadata| metadata.len() > 0) {
        destination
    } else {
        wallpaper.to_path_buf()
    }
}

fn smart_mode_variant(image: &Path) -> (&'static str, &'static str) {
    let pixels = sample_pixels(image, 16);
    if pixels.is_empty() {
        return ("dark", "tonal-spot");
    }
    let count = pixels.len() as f64;
    let red = pixels.iter().map(|pixel| pixel.0).sum::<f64>() / count;
    let green = pixels.iter().map(|pixel| pixel.1).sum::<f64>() / count;
    let blue = pixels.iter().map(|pixel| pixel.2).sum::<f64>() / count;
    let lightness = (red.max(green).max(blue) + red.min(green).min(blue)) / 2.0;
    let mode = if lightness > 0.60 { "light" } else { "dark" };
    let rg = pixels
        .iter()
        .map(|(red, green, _)| (red - green).abs())
        .collect::<Vec<_>>();
    let yb = pixels
        .iter()
        .map(|(red, green, blue)| (0.5 * (red + green) - blue).abs())
        .collect::<Vec<_>>();
    let colourfulness = (stddev(&rg).powi(2) + stddev(&yb).powi(2)).sqrt()
        + 0.3 * (mean(&rg).powi(2) + mean(&yb).powi(2)).sqrt();
    let variant = if colourfulness < 0.02 {
        "neutral"
    } else if colourfulness < 0.05 {
        "content"
    } else {
        "tonal-spot"
    };
    (mode, variant)
}

fn mean(values: &[f64]) -> f64 {
    values.iter().sum::<f64>() / values.len() as f64
}

fn stddev(values: &[f64]) -> f64 {
    let average = mean(values);
    (values
        .iter()
        .map(|value| (value - average).powi(2))
        .sum::<f64>()
        / values.len() as f64)
        .sqrt()
}

fn matugen_image(image: &Path, settings: &Map<String, Value>) -> Result<MaterialColors, String> {
    let scheme = setting_string(settings, "dynamicScheme")
        .filter(|value| SCHEMES.contains(value))
        .unwrap_or("tonal-spot");
    let contrast = setting_float(settings, "dynamicContrast", 0.0)
        .unwrap_or(0.0)
        .clamp(-1.0, 1.0);
    let mode = setting_string(settings, "dynamicMode")
        .filter(|value| *value == "light" || *value == "dark")
        .unwrap_or("smart");
    let prefer = setting_string(settings, "dynamicPrefer")
        .filter(|value| PREFERS.contains(value))
        .unwrap_or("saturation");
    let type_arg = format!("scheme-{scheme}");
    let contrast_arg = format_general(contrast);
    let output = Command::new("matugen")
        .arg("image")
        .arg(image)
        .args([
            "--type",
            &type_arg,
            "--contrast",
            &contrast_arg,
            "--mode",
            mode,
            "--prefer",
            prefer,
            "--json",
            "hex",
        ])
        .output()
        .map_err(|error| format!("could not start matugen: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    let document: Value = serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("matugen returned invalid JSON: {error}"))?;
    let color_objects = document
        .get("colors")
        .and_then(Value::as_object)
        .ok_or_else(|| "matugen output has no colors object".to_owned())?;
    let mut colors = MaterialColors::new();
    for (key, value) in color_objects {
        if let Some(color) = value
            .get("default")
            .and_then(|default| default.get("color"))
            .and_then(Value::as_str)
        {
            colors.insert(key.clone(), color.to_owned());
        }
    }
    Ok(colors)
}

fn setting_float(settings: &Map<String, Value>, key: &str, default: f64) -> Option<f64> {
    let value = settings.get(key)?;
    if value.is_null() || value == false || value == 0 || value == "" {
        return Some(0.0);
    }
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
        .or(Some(default))
}

fn format_general(value: f64) -> String {
    if value == 0.0 {
        return "0".to_owned();
    }
    let exponent = value.abs().log10().floor() as i32;
    if exponent < -4 {
        let mut value = format!("{value:.5e}");
        if let Some((mantissa, exponent)) = value.split_once('e') {
            let mantissa = mantissa.trim_end_matches('0').trim_end_matches('.');
            let exponent = exponent.parse::<i32>().unwrap_or_default();
            value = format!("{mantissa}e{exponent:+}");
        }
        value
    } else {
        let decimals = (5 - exponent).max(0) as usize;
        let mut value = format!("{value:.decimals$}");
        if value.contains('.') {
            value = value.trim_end_matches('0').trim_end_matches('.').to_owned();
        }
        value
    }
}

fn matugen_terminal(source: &str) -> Result<Value, String> {
    let output = Command::new("matugen")
        .args(["color", "hex", source, "-m", "dark", "-j", "hex"])
        .output()
        .map_err(|error| format!("could not start matugen: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("matugen returned invalid JSON: {error}"))
}

fn terminal_colors(base16: &Value) -> Option<MaterialColors> {
    let base16 = base16.get("base16")?.as_object()?;
    let mut colors = MaterialColors::new();
    for (key, value) in base16 {
        let color = value.get("dark")?.get("color")?.as_str()?.to_owned();
        colors.insert(key.clone(), color);
    }
    Some(colors)
}

fn render_kitty(terminal: &MaterialColors, pill: &Map<String, Value>) -> Result<String, String> {
    let terminal_color = |key: &str| {
        terminal
            .get(key)
            .ok_or_else(|| format!("matugen omitted {key}"))
    };
    let pill_color = |key: &str| palette_color(pill, key).ok_or_else(|| format!("missing {key}"));
    let mut lines = vec![
        format!("background {}", terminal_color("base00")?),
        format!("foreground {}", terminal_color("base07")?),
        format!("cursor {}", pill_color("primary")?),
        format!("cursor_text_color {}", terminal_color("base00")?),
        format!("selection_background {}", terminal_color("base02")?),
        format!("selection_foreground {}", terminal_color("base07")?),
    ];
    for (index, key) in TERMINAL_ANSI.iter().enumerate() {
        lines.push(format!(
            "color{index} {}",
            terminal_color(&format!("base{key}"))?
        ));
    }
    Ok(lines.join("\n") + "\n")
}

fn render_fastfetch(pill: &Map<String, Value>) -> Result<(), String> {
    let directory = home().join(".config/fastfetch");
    let template = directory.join("config.jsonc.in");
    if !template.is_file() {
        eprintln!(
            "wallcolors: config.jsonc.in missing in ~/.config/fastfetch, skipping fastfetch recolour (re-run the installer)"
        );
        return Ok(());
    }
    let ansi = |key| ansi_rgb(required_color(pill, key)?);
    let replacements = [
        (
            "__LANTERN__",
            directory.join("lantern.txt").display().to_string(),
        ),
        ("__KEYS__", ansi("primary")?),
        ("__SEP__", ansi("dim")?),
        ("__LOGO1__", ansi("primary")?),
        ("__LOGO2__", ansi("on_primary_container")?),
        ("__LOGO3__", ansi("surface_container")?),
        ("__LOGO4__", ansi("surface_container_high")?),
        ("__LOGO5__", ansi("subtle")?),
        ("__LOGO6__", ansi("outline")?),
        ("__LOGO7__", ansi("bright")?),
    ];
    let mut output = fs::read_to_string(&template)
        .map_err(|error| format!("could not read {}: {error}", template.display()))?;
    for (key, value) in replacements {
        output = output.replace(key, &value);
    }
    let path = directory.join("config.jsonc");
    write_atomic(&path, &output)
        .map_err(|error| format!("could not write {}: {error}", path.display()))
}

fn ansi_rgb(color: &str) -> Result<String, String> {
    let (red, green, blue) = parse_hex(color)?;
    Ok(format!(
        "{};{};{}",
        (red * 255.0).round() as u8,
        (green * 255.0).round() as u8,
        (blue * 255.0).round() as u8
    ))
}

fn write_atomic(path: &Path, contents: &str) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("wallcolors");
    let temporary = path.with_file_name(format!("{name}.{}.tmp", std::process::id()));
    fs::write(&temporary, contents)?;
    fs::rename(temporary, path)
}

fn hsl_palette(hue: f64, saturation: f64, mean_lightness: f64) -> Map<String, Value> {
    let chromatic = saturation > 0.02;
    let light_mode = mean_lightness >= 0.40;
    let surface_saturation = if light_mode {
        saturation.min(0.26)
    } else {
        saturation.max(if chromatic { 0.30 } else { 0.0 }).min(0.45)
    };
    let accent_saturation = if chromatic {
        if light_mode {
            (saturation + 0.18).min(0.85)
        } else {
            (saturation.max(0.30) + 0.12).min(0.82)
        }
    } else {
        0.05
    };
    let (base, steps, text, accent_lightness, deep_lightness, glow_lightness) = if light_mode {
        (
            lerp(mean_lightness, 0.40, 0.66, 0.80, 0.93),
            LIGHT_STEPS,
            LIGHT_TEXT,
            0.42,
            0.30,
            0.55,
        )
    } else {
        (
            lerp(mean_lightness, 0.0, 0.40, 0.045, 0.20),
            DARK_STEPS,
            DARK_TEXT,
            0.70,
            0.34,
            0.86,
        )
    };
    let mut pill = Map::new();
    for (name, step) in SURF_NAMES.iter().zip(steps) {
        pill.insert(
            name.to_string(),
            json!(tint(hue, surface_saturation, base + step)),
        );
    }
    pill.insert(
        "primary".to_owned(),
        json!(tint(hue, accent_saturation, accent_lightness)),
    );
    pill.insert(
        "primary_container".to_owned(),
        json!(tint(
            hue,
            (accent_saturation + 0.08).min(0.9),
            deep_lightness
        )),
    );
    pill.insert(
        "on_primary_container".to_owned(),
        json!(tint(hue, accent_saturation.min(0.45), glow_lightness)),
    );
    pill.insert(
        "outline".to_owned(),
        json!(tint(
            hue,
            surface_saturation,
            base + if light_mode { -0.35 } else { 0.35 }
        )),
    );
    for (key, (lightness, saturation)) in TEXT_KEYS.iter().zip(text) {
        pill.insert(key.to_string(), json!(tint(hue, saturation, lightness)));
    }
    pill.insert("light".to_owned(), json!(light_mode));
    pill
}

fn material_palette(
    colors: &MaterialColors,
    settings: &Map<String, Value>,
) -> Result<Map<String, Value>, String> {
    for key in [
        "surface",
        "surface_container_low",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
        "primary",
        "primary_container",
        "secondary_container",
        "tertiary_container",
        "on_primary_container",
        "outline",
        "outline_variant",
        "on_surface",
        "on_surface_variant",
        "on_primary",
        "secondary",
        "tertiary",
    ] {
        parse_hex(
            colors
                .get(key)
                .ok_or_else(|| format!("matugen omitted {key}"))?,
        )?;
    }
    let surface = colors["surface"].as_str();
    let on_surface = colors["on_surface"].as_str();
    let on_surface_variant = colors["on_surface_variant"].as_str();
    let light_mode = is_light(surface)?;

    let mut raw = Map::new();
    for key in [
        "surface",
        "surface_container_low",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
        "primary",
        "primary_container",
        "secondary_container",
        "tertiary_container",
        "on_primary_container",
        "outline",
        "outline_variant",
    ] {
        raw.insert(key.to_owned(), json!(colors[key]));
    }
    raw.insert("cream".to_owned(), json!(on_surface));
    raw.insert(
        "bright".to_owned(),
        json!(mix_hex(
            on_surface,
            if light_mode { "#000000" } else { "#ffffff" },
            0.32
        )?),
    );
    raw.insert(
        "subtle".to_owned(),
        json!(mix_hex(on_surface, on_surface_variant, 0.50)?),
    );
    raw.insert("dim".to_owned(), json!(on_surface_variant));
    raw.insert(
        "faint".to_owned(),
        json!(mix_hex(on_surface_variant, surface, 0.42)?),
    );
    raw.insert("icon_dim".to_owned(), json!(on_surface_variant));
    raw.insert("tick_rest".to_owned(), json!(on_surface_variant));
    raw.insert("light".to_owned(), json!(light_mode));
    raw.insert("on_surface".to_owned(), json!(on_surface));
    raw.insert("on_surface_variant".to_owned(), json!(on_surface_variant));
    raw.insert("on_primary".to_owned(), json!(colors["on_primary"]));
    raw.insert("secondary".to_owned(), json!(colors["secondary"]));
    raw.insert("tertiary".to_owned(), json!(colors["tertiary"]));

    let vague = vague_style_transform(colors, light_mode)?;
    let mut palette = Map::new();
    for (key, value) in &raw {
        if key == "light" {
            palette.insert(key.clone(), value.clone());
        } else {
            let color = value
                .as_str()
                .ok_or_else(|| format!("invalid palette value: {key}"))?;
            if let Some(vague_color) = vague.get(key).and_then(Value::as_str) {
                palette.insert(key.clone(), json!(mix_hex(color, vague_color, 0.7)?));
            } else {
                palette.insert(key.clone(), value.clone());
            }
        }
    }

    let mut container_saturation =
        setting_float(settings, "containerSaturation", 1.0).unwrap_or(1.0);
    container_saturation = container_saturation.clamp(0.0, 2.0);
    if (container_saturation - 1.0).abs() > 0.001 {
        for key in CONTAINER_KEYS {
            let color = palette_color(&palette, key).ok_or_else(|| format!("missing {key}"))?;
            palette.insert(
                key.to_owned(),
                json!(scale_saturation(color, container_saturation)?),
            );
        }
    }

    let role = setting_string(settings, "surfaceRole").unwrap_or("default");
    let role_key = match role {
        "surface" => "surface",
        "surface_container_low" => "surface_container_low",
        "surface_container" => "surface_container",
        "surface_container_high" => "surface_container_high",
        "surface_container_highest" => "surface_container_highest",
        "primary_container" => "primary_container",
        "secondary_container" => "secondary_container",
        "tertiary_container" => "tertiary_container",
        _ => "surface",
    };
    let base = palette_color(&palette, role_key)
        .ok_or_else(|| format!("missing surface role {role_key}"))?
        .to_owned();
    if role_key != "surface" {
        let base_lightness = hex_hls(&base)?.1;
        let surface_lightness = hex_hls(
            palette_color(&palette, "surface").ok_or_else(|| "missing surface".to_owned())?,
        )?
        .1;
        let ramp_keys = [
            "surface_container_low",
            "surface_container",
            "surface_container_high",
            "surface_container_highest",
        ];
        let deltas = ramp_keys
            .iter()
            .map(|key| {
                let lightness =
                    hex_hls(palette_color(&palette, key).ok_or_else(|| format!("missing {key}"))?)?
                        .1;
                Ok((*key, lightness - surface_lightness))
            })
            .collect::<Result<Vec<_>, String>>()?;
        palette.insert("surface".to_owned(), json!(base));
        for (key, delta) in &deltas {
            palette.insert(
                (*key).to_owned(),
                json!(with_lightness(&base, base_lightness + delta)?),
            );
        }
        let mut scale = 1.0;
        for _ in 0..4 {
            let ramp = [
                palette_color(&palette, "surface").unwrap().to_owned(),
                palette_color(&palette, "surface_container_low")
                    .unwrap()
                    .to_owned(),
                palette_color(&palette, "surface_container")
                    .unwrap()
                    .to_owned(),
                palette_color(&palette, "surface_container_high")
                    .unwrap()
                    .to_owned(),
                palette_color(&palette, "surface_container_highest")
                    .unwrap()
                    .to_owned(),
            ];
            let ink = best_extreme(&ramp)?;
            if ramp
                .iter()
                .map(|background| contrast_ratio(&ink, background))
                .collect::<Result<Vec<_>, _>>()?
                .into_iter()
                .fold(f64::INFINITY, f64::min)
                >= 4.5
            {
                break;
            }
            scale *= 0.5;
            for (key, delta) in &deltas {
                palette.insert(
                    (*key).to_owned(),
                    json!(with_lightness(&base, base_lightness + delta * scale)?),
                );
            }
        }
        if matches!(
            role_key,
            "primary_container" | "secondary_container" | "tertiary_container"
        ) {
            let fallback_ink = if is_light(&base)? {
                "#1c1b1f"
            } else {
                "#e6e1e5"
            };
            let ink = colors
                .get(&format!("on_{role_key}"))
                .map(String::as_str)
                .unwrap_or(fallback_ink);
            retone_text(&mut palette, ink, &base)?;
        } else if contrast_ratio(
            palette_color(&palette, "cream").ok_or_else(|| "missing cream".to_owned())?,
            &base,
        )? < 4.5
        {
            let ink = if is_light(&base)? {
                "#151317"
            } else {
                "#f7f4f8"
            };
            retone_text(&mut palette, ink, &base)?;
        }
        palette.insert("light".to_owned(), json!(is_light(&base)?));
    }

    let ramp = [
        palette_color(&palette, "surface_container_low")
            .ok_or_else(|| "missing surface_container_low".to_owned())?
            .to_owned(),
        palette_color(&palette, "surface")
            .ok_or_else(|| "missing surface".to_owned())?
            .to_owned(),
        palette_color(&palette, "surface_container_high")
            .ok_or_else(|| "missing surface_container_high".to_owned())?
            .to_owned(),
        palette_color(&palette, "surface_container_highest")
            .ok_or_else(|| "missing surface_container_highest".to_owned())?
            .to_owned(),
    ];
    let primary = palette_color(&palette, "primary")
        .ok_or_else(|| "missing primary".to_owned())?
        .to_owned();
    palette.insert("primary".to_owned(), json!(walk_ink(&primary, &ramp, 3.0)?));
    for (fill_key, ink_key) in [
        ("primary", "on_primary"),
        ("primary_container", "on_primary_container"),
    ] {
        let fill = palette_color(&palette, fill_key)
            .ok_or_else(|| format!("missing {fill_key}"))?
            .to_owned();
        let ink = palette_color(&palette, ink_key)
            .ok_or_else(|| format!("missing {ink_key}"))?
            .to_owned();
        palette.insert(ink_key.to_owned(), json!(walk_ink(&ink, &[fill], 4.5)?));
    }
    for (key, target) in [
        ("on_surface", 4.5),
        ("on_surface_variant", 4.5),
        ("cream", 4.5),
        ("bright", 4.5),
        ("subtle", 4.5),
        ("dim", 4.5),
        ("icon_dim", 3.5),
        ("tick_rest", 3.5),
        ("faint", 3.0),
    ] {
        let ink = palette_color(&palette, key)
            .ok_or_else(|| format!("missing {key}"))?
            .to_owned();
        palette.insert(key.to_owned(), json!(walk_ink(&ink, &ramp, target)?));
    }
    Ok(palette)
}

fn vague_style_transform(
    colors: &MaterialColors,
    light_mode: bool,
) -> Result<Map<String, Value>, String> {
    let vague_hue = 0.66;
    let mut vague = Map::new();
    for (key, multiplier) in [("primary", 0.45), ("secondary", 0.4), ("tertiary", 0.35)] {
        vague.insert(
            key.to_owned(),
            json!(desaturate_toward_vague(
                &colors[key],
                multiplier,
                vague_hue
            )?),
        );
    }
    for key in [
        "surface",
        "surface_container_low",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
    ] {
        vague.insert(
            key.to_owned(),
            json!(cool_surface(&colors[key], vague_hue)?),
        );
    }
    let on_surface = if light_mode { "#2d2b3d" } else { "#c8c6d1" };
    let on_surface_variant = if light_mode { "#5d5b6d" } else { "#b8b6c6" };
    let fixed = [
        ("on_surface", on_surface),
        ("on_surface_variant", on_surface_variant),
        ("cream", on_surface),
        ("bright", if light_mode { "#181628" } else { "#e0dff0" }),
        ("subtle", if light_mode { "#686678" } else { "#b8b6c6" }),
        ("dim", on_surface_variant),
        ("faint", if light_mode { "#787688" } else { "#8a8896" }),
        ("icon_dim", on_surface_variant),
        ("tick_rest", if light_mode { "#585668" } else { "#b8b6c6" }),
        ("on_primary", on_surface),
        (
            "on_primary_container",
            if light_mode { "#2d2b3d" } else { "#c8c6d1" },
        ),
        ("outline", if light_mode { "#a0a0b8" } else { "#606079" }),
        (
            "outline_variant",
            if light_mode { "#78788c" } else { "#4a4a5e" },
        ),
    ];
    for (key, value) in fixed {
        vague.insert(key.to_owned(), json!(value));
    }
    let (_, primary_container_lightness, primary_container_saturation) =
        rgb_to_hls(parse_hex(&colors["primary_container"])?);
    vague.insert(
        "primary_container".to_owned(),
        json!(hsl_hex(
            vague_hue,
            primary_container_saturation * 0.4,
            primary_container_lightness
        )),
    );
    for key in ["secondary_container", "tertiary_container"] {
        let (_, lightness, saturation) = rgb_to_hls(parse_hex(&colors[key])?);
        vague.insert(
            key.to_owned(),
            json!(hsl_hex(vague_hue, saturation * 0.4, lightness)),
        );
    }
    vague.insert("light".to_owned(), json!(light_mode));
    Ok(vague)
}

fn desaturate_toward_vague(color: &str, multiplier: f64, hue_shift: f64) -> Result<String, String> {
    let (hue, lightness, saturation) = rgb_to_hls(parse_hex(color)?);
    let new_hue = hue + (hue_shift - hue) * 0.6;
    Ok(hsl_hex(new_hue, saturation * multiplier, lightness))
}

fn cool_surface(color: &str, hue: f64) -> Result<String, String> {
    let (_, lightness, saturation) = rgb_to_hls(parse_hex(color)?);
    Ok(hsl_hex(hue, (saturation * 0.15).min(0.08), lightness))
}

fn retone_text(palette: &mut Map<String, Value>, ink: &str, base: &str) -> Result<(), String> {
    let extreme = best_extreme(&[base.to_owned()])?;
    palette.insert("cream".to_owned(), json!(ink));
    palette.insert("on_surface".to_owned(), json!(ink));
    palette.insert("bright".to_owned(), json!(mix_hex(ink, &extreme, 0.32)?));
    palette.insert("subtle".to_owned(), json!(mix_hex(ink, base, 0.38)?));
    palette.insert("dim".to_owned(), json!(mix_hex(ink, base, 0.58)?));
    palette.insert("faint".to_owned(), json!(mix_hex(ink, base, 0.72)?));
    let subtle = palette["subtle"].clone();
    palette.insert("icon_dim".to_owned(), subtle.clone());
    palette.insert("tick_rest".to_owned(), subtle);
    Ok(())
}

fn walk_ink(ink: &str, backgrounds: &[String], target: f64) -> Result<String, String> {
    if backgrounds
        .iter()
        .map(|background| contrast_ratio(ink, background))
        .collect::<Result<Vec<_>, _>>()?
        .iter()
        .all(|ratio| *ratio >= target)
    {
        return Ok(ink.to_owned());
    }
    let extreme = best_extreme(backgrounds)?;
    for amount in [0.12, 0.24, 0.36, 0.48, 0.6, 0.75, 0.9, 1.0] {
        let candidate = mix_hex(ink, &extreme, amount)?;
        if backgrounds
            .iter()
            .map(|background| contrast_ratio(&candidate, background))
            .collect::<Result<Vec<_>, _>>()?
            .iter()
            .all(|ratio| *ratio >= target)
        {
            return Ok(candidate);
        }
    }
    Ok(extreme)
}

fn palette_color<'a>(palette: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    palette.get(key).and_then(Value::as_str)
}

fn required_color<'a>(palette: &'a Map<String, Value>, key: &str) -> Result<&'a str, String> {
    palette_color(palette, key).ok_or_else(|| format!("missing {key}"))
}

fn parse_hex(color: &str) -> Result<Rgb, String> {
    let color = color.strip_prefix('#').unwrap_or(color);
    if color.len() != 6 || !color.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(format!("invalid color: {color}"));
    }
    let red =
        u8::from_str_radix(&color[0..2], 16).map_err(|_| format!("invalid color: {color}"))?;
    let green =
        u8::from_str_radix(&color[2..4], 16).map_err(|_| format!("invalid color: {color}"))?;
    let blue =
        u8::from_str_radix(&color[4..6], 16).map_err(|_| format!("invalid color: {color}"))?;
    Ok((
        red as f64 / 255.0,
        green as f64 / 255.0,
        blue as f64 / 255.0,
    ))
}

fn rgb_to_hls((red, green, blue): Rgb) -> (f64, f64, f64) {
    let max = red.max(green).max(blue);
    let min = red.min(green).min(blue);
    let lightness = (max + min) / 2.0;
    if max == min {
        return (0.0, lightness, 0.0);
    }
    let delta = max - min;
    let saturation = if lightness <= 0.5 {
        delta / (max + min)
    } else {
        delta / (2.0 - max - min)
    };
    let red_delta = (max - red) / delta;
    let green_delta = (max - green) / delta;
    let blue_delta = (max - blue) / delta;
    let mut hue = if red == max {
        blue_delta - green_delta
    } else if green == max {
        2.0 + red_delta - blue_delta
    } else {
        4.0 + green_delta - red_delta
    };
    hue = (hue / 6.0).rem_euclid(1.0);
    (hue, lightness, saturation)
}

fn hls_to_rgb(hue: f64, lightness: f64, saturation: f64) -> Rgb {
    let lightness = lightness.clamp(0.0, 1.0);
    let saturation = saturation.clamp(0.0, 1.0);
    if saturation == 0.0 {
        return (lightness, lightness, lightness);
    }
    let m2 = if lightness <= 0.5 {
        lightness * (1.0 + saturation)
    } else {
        lightness + saturation - lightness * saturation
    };
    let m1 = 2.0 * lightness - m2;
    (
        hue_to_rgb(m1, m2, hue.rem_euclid(1.0) + 1.0 / 3.0),
        hue_to_rgb(m1, m2, hue.rem_euclid(1.0)),
        hue_to_rgb(m1, m2, hue.rem_euclid(1.0) - 1.0 / 3.0),
    )
}

fn hue_to_rgb(m1: f64, m2: f64, mut hue: f64) -> f64 {
    if hue < 0.0 {
        hue += 1.0;
    }
    if hue > 1.0 {
        hue -= 1.0;
    }
    if hue < 1.0 / 6.0 {
        m1 + (m2 - m1) * hue * 6.0
    } else if hue < 0.5 {
        m2
    } else if hue < 2.0 / 3.0 {
        m1 + (m2 - m1) * (2.0 / 3.0 - hue) * 6.0
    } else {
        m1
    }
}

fn hsl_hex(hue: f64, saturation: f64, lightness: f64) -> String {
    rgb_hex(hls_to_rgb(
        hue,
        lightness.clamp(0.0, 1.0),
        saturation.clamp(0.0, 1.0),
    ))
}

fn rgb_hex((red, green, blue): Rgb) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        py_round(red * 255.0),
        py_round(green * 255.0),
        py_round(blue * 255.0)
    )
}

fn py_round(value: f64) -> u8 {
    let floor = value.floor();
    let fraction = value - floor;
    let rounded = match fraction.partial_cmp(&0.5).unwrap_or(Ordering::Less) {
        Ordering::Less => floor,
        Ordering::Greater => floor + 1.0,
        Ordering::Equal => {
            if (floor as i64) % 2 == 0 {
                floor
            } else {
                floor + 1.0
            }
        }
    };
    rounded.clamp(0.0, 255.0) as u8
}

fn tint(hue: f64, saturation: f64, lightness: f64) -> String {
    hsl_hex(hue, saturation, lightness)
}

fn lerp(value: f64, start: f64, end: f64, low: f64, high: f64) -> f64 {
    let amount = ((value - start) / (end - start)).clamp(0.0, 1.0);
    low + amount * (high - low)
}

fn mix_hex(first: &str, second: &str, amount: f64) -> Result<String, String> {
    let first = parse_hex(first)?;
    let second = parse_hex(second)?;
    Ok(rgb_hex((
        first.0 + (second.0 - first.0) * amount,
        first.1 + (second.1 - first.1) * amount,
        first.2 + (second.2 - first.2) * amount,
    )))
}

fn is_light(color: &str) -> Result<bool, String> {
    let (red, green, blue) = parse_hex(color)?;
    Ok(0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.5)
}

fn hex_hls(color: &str) -> Result<(f64, f64, f64), String> {
    Ok(rgb_to_hls(parse_hex(color)?))
}

fn with_lightness(color: &str, lightness: f64) -> Result<String, String> {
    let (hue, _, saturation) = hex_hls(color)?;
    Ok(hsl_hex(hue, saturation, lightness.clamp(0.02, 0.98)))
}

fn scale_saturation(color: &str, amount: f64) -> Result<String, String> {
    let (hue, lightness, saturation) = hex_hls(color)?;
    Ok(hsl_hex(
        hue,
        (saturation * amount).clamp(0.0, 1.0),
        lightness,
    ))
}

fn relative_luminance(color: &str) -> Result<f64, String> {
    let (red, green, blue) = parse_hex(color)?;
    let linear = |channel: f64| {
        if channel <= 0.03928 {
            channel / 12.92
        } else {
            ((channel + 0.055) / 1.055).powf(2.4)
        }
    };
    Ok(0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue))
}

fn contrast_ratio(first: &str, second: &str) -> Result<f64, String> {
    let first = relative_luminance(first)?;
    let second = relative_luminance(second)?;
    let (light, dark) = if first >= second {
        (first, second)
    } else {
        (second, first)
    };
    Ok((light + 0.05) / (dark + 0.05))
}

fn best_extreme(backgrounds: &[String]) -> Result<String, String> {
    let mut black = f64::INFINITY;
    let mut white = f64::INFINITY;
    for background in backgrounds {
        black = black.min(contrast_ratio("#000000", background)?);
        white = white.min(contrast_ratio("#ffffff", background)?);
    }
    Ok(if black >= white {
        "#000000".to_owned()
    } else {
        "#ffffff".to_owned()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_material_colors() -> MaterialColors {
        [
            ("surface", "#1c1b1f"),
            ("surface_container_low", "#211f26"),
            ("surface_container", "#25232a"),
            ("surface_container_high", "#2b2930"),
            ("surface_container_highest", "#36343b"),
            ("primary", "#d0bcff"),
            ("primary_container", "#4f378b"),
            ("secondary_container", "#4a4458"),
            ("tertiary_container", "#633b48"),
            ("on_primary_container", "#eaddff"),
            ("outline", "#938f99"),
            ("outline_variant", "#49454f"),
            ("on_surface", "#e6e1e5"),
            ("on_surface_variant", "#cac4d0"),
            ("on_primary", "#381e72"),
            ("secondary", "#ccc2dc"),
            ("tertiary", "#efb8c8"),
        ]
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect()
    }

    #[test]
    fn manual_hsl_palette_has_expected_roles_and_lightness() {
        let dark = hsl_palette(0.0, 0.5, 0.12);
        let light = hsl_palette(0.0, 0.5, 0.85);
        assert_eq!(dark["light"], false);
        assert_eq!(light["light"], true);
        assert_eq!(dark["primary"], "#e28383");
        assert!(palette_color(&dark, "surface").is_some());
        assert!(palette_color(&light, "on_primary_container").is_some());
    }

    #[test]
    fn histogram_ignores_neutral_dominance_and_weights_chromatic_pixels() {
        let output = "  9300: (128,128,128) #808080 gray\n  700: (255,0,0) #ff0000 red\n";
        let (hue, lightness) = analyze_histogram(output);
        assert!(hue.is_none());
        assert!(lightness > 0.49 && lightness < 0.51);
        let output = " 1000: (255,0,0) #ff0000 red\n 100: (0,0,255) #0000ff blue\n";
        let (hue, _) = analyze_histogram(output);
        assert!(hue.is_some());
    }

    #[test]
    fn contrast_helpers_choose_black_on_mid_gray() {
        assert_eq!(best_extreme(&["#7e7e7e".to_owned()]).unwrap(), "#000000");
        assert!(contrast_ratio("#000000", "#7e7e7e").unwrap() > 4.5);
    }

    #[test]
    fn material_palette_recenters_surface_and_keeps_text_readable() {
        let colors = sample_material_colors();
        let settings = serde_json::from_value(json!({
            "surfaceRole": "primary_container",
            "containerSaturation": 1.2
        }))
        .unwrap();
        let palette = material_palette(&colors, &settings).unwrap();
        assert_eq!(palette["surface"], palette["primary_container"]);
        assert_eq!(palette["light"], false);
        for key in ["cream", "bright", "subtle", "dim", "on_surface"] {
            let ink = palette_color(&palette, key).unwrap();
            assert!(
                contrast_ratio(ink, palette_color(&palette, "surface").unwrap()).unwrap() >= 4.5
            );
        }
    }
}
