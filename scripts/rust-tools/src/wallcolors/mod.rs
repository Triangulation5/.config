mod color;
mod image_sample;
mod scheme;
mod targets;

use crate::config::{flags, home};
use color::tint;
use image_sample::{analyze, smart_mode_variant, wallpaper_thumbnail};
use scheme::{hsl_palette, material_palette, palette_color, setting_string};
use serde_json::{json, Map, Value};
use std::{
    fs,
    path::{Path, PathBuf},
};
use targets::{
    matugen_image, matugen_terminal, render_fastfetch, render_kitty, terminal_colors, write_atomic,
};

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

#[cfg(test)]
mod tests {
    use super::{
        color::{best_extreme, contrast_ratio},
        image_sample::analyze_histogram,
        scheme::{hsl_palette, material_palette, palette_color, MaterialColors},
    };
    use serde_json::json;

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
