use super::{
    color::parse_hex,
    scheme::{palette_color, required_color, setting_float, setting_string, MaterialColors},
};
use crate::config::home;
use serde_json::{Map, Value};
use std::{fs, io, path::Path, process::Command};

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
const TERMINAL_ANSI: [&str; 16] = [
    "00", "08", "0b", "0a", "0d", "0e", "0c", "05", "03", "08", "0b", "0a", "0d", "0e", "0c", "07",
];

pub(super) fn matugen_image(
    image: &Path,
    settings: &Map<String, Value>,
) -> Result<MaterialColors, String> {
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

pub(super) fn matugen_terminal(source: &str) -> Result<Value, String> {
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

pub(super) fn terminal_colors(base16: &Value) -> Option<MaterialColors> {
    let base16 = base16.get("base16")?.as_object()?;
    let mut colors = MaterialColors::new();
    for (key, value) in base16 {
        let color = value.get("dark")?.get("color")?.as_str()?.to_owned();
        colors.insert(key.clone(), color);
    }
    Some(colors)
}

pub(super) fn render_kitty(
    terminal: &MaterialColors,
    pill: &Map<String, Value>,
) -> Result<String, String> {
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

pub(super) fn render_fastfetch(pill: &Map<String, Value>) -> Result<(), String> {
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

pub(super) fn write_atomic(path: &Path, contents: &str) -> io::Result<()> {
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
