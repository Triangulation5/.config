use super::color::{
    best_extreme, contrast_ratio, hex_hls, hsl_hex, is_light, lerp, mix_hex, parse_hex, rgb_to_hls,
    scale_saturation, tint, walk_ink, with_lightness,
};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;

pub(super) type MaterialColors = BTreeMap<String, String>;

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

pub(super) fn setting_string<'a>(settings: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    settings.get(key).and_then(Value::as_str)
}

pub(super) fn setting_float(settings: &Map<String, Value>, key: &str, default: f64) -> Option<f64> {
    let value = settings.get(key)?;
    if value.is_null() || value == false || value == 0 || value == "" {
        return Some(0.0);
    }
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
        .or(Some(default))
}

pub(super) fn palette_color<'a>(palette: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    palette.get(key).and_then(Value::as_str)
}

pub(super) fn required_color<'a>(
    palette: &'a Map<String, Value>,
    key: &str,
) -> Result<&'a str, String> {
    palette_color(palette, key).ok_or_else(|| format!("missing {key}"))
}

pub(super) fn hsl_palette(hue: f64, saturation: f64, mean_lightness: f64) -> Map<String, Value> {
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

pub(super) fn material_palette(
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

    let container_saturation = setting_float(settings, "containerSaturation", 1.0)
        .unwrap_or(1.0)
        .clamp(0.0, 2.0);
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
        "surface"
        | "surface_container_low"
        | "surface_container"
        | "surface_container_high"
        | "surface_container_highest"
        | "primary_container"
        | "secondary_container"
        | "tertiary_container" => role,
        _ => "surface",
    };
    let base = palette_color(&palette, role_key)
        .ok_or_else(|| format!("missing surface role {role_key}"))?
        .to_owned();
    if role_key != "surface" {
        recenter_surface_role(&mut palette, colors, role_key, &base)?;
    }

    let ramp = [
        required_color(&palette, "surface_container_low")?.to_owned(),
        required_color(&palette, "surface")?.to_owned(),
        required_color(&palette, "surface_container_high")?.to_owned(),
        required_color(&palette, "surface_container_highest")?.to_owned(),
    ];
    let primary = required_color(&palette, "primary")?.to_owned();
    palette.insert("primary".to_owned(), json!(walk_ink(&primary, &ramp, 3.0)?));
    for (fill_key, ink_key) in [
        ("primary", "on_primary"),
        ("primary_container", "on_primary_container"),
    ] {
        let fill = required_color(&palette, fill_key)?.to_owned();
        let ink = required_color(&palette, ink_key)?.to_owned();
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
        let ink = required_color(&palette, key)?.to_owned();
        palette.insert(key.to_owned(), json!(walk_ink(&ink, &ramp, target)?));
    }
    Ok(palette)
}

fn recenter_surface_role(
    palette: &mut Map<String, Value>,
    colors: &MaterialColors,
    role_key: &str,
    base: &str,
) -> Result<(), String> {
    let base_lightness = hex_hls(base)?.1;
    let surface_lightness = hex_hls(required_color(palette, "surface")?)?.1;
    let ramp_keys = [
        "surface_container_low",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
    ];
    let deltas = ramp_keys
        .iter()
        .map(|key| {
            let lightness = hex_hls(required_color(palette, key)?)?.1;
            Ok((*key, lightness - surface_lightness))
        })
        .collect::<Result<Vec<_>, String>>()?;
    palette.insert("surface".to_owned(), json!(base));
    for (key, delta) in &deltas {
        palette.insert(
            (*key).to_owned(),
            json!(with_lightness(base, base_lightness + delta)?),
        );
    }
    let mut scale = 1.0;
    for _ in 0..4 {
        let ramp = [
            required_color(palette, "surface")?.to_owned(),
            required_color(palette, "surface_container_low")?.to_owned(),
            required_color(palette, "surface_container")?.to_owned(),
            required_color(palette, "surface_container_high")?.to_owned(),
            required_color(palette, "surface_container_highest")?.to_owned(),
        ];
        let ink = best_extreme(&ramp)?;
        let mut min_ratio = f64::INFINITY;
        for bg in &ramp {
            min_ratio = min_ratio.min(contrast_ratio(&ink, bg)?);
        }
        if min_ratio >= 4.5 {
            break;
        }
        scale *= 0.5;
        for (key, delta) in &deltas {
            palette.insert(
                (*key).to_owned(),
                json!(with_lightness(base, base_lightness + delta * scale)?),
            );
        }
    }
    if matches!(
        role_key,
        "primary_container" | "secondary_container" | "tertiary_container"
    ) {
        let fallback_ink = if is_light(base)? {
            "#1c1b1f"
        } else {
            "#e6e1e5"
        };
        let ink = colors
            .get(&format!("on_{role_key}"))
            .map(String::as_str)
            .unwrap_or(fallback_ink);
        retone_text(palette, ink, base)?;
    } else if contrast_ratio(required_color(palette, "cream")?, base)? < 4.5 {
        let ink = if is_light(base)? {
            "#151317"
        } else {
            "#f7f4f8"
        };
        retone_text(palette, ink, base)?;
    }
    palette.insert("light".to_owned(), json!(is_light(base)?));
    Ok(())
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
            json!(desaturate_toward_vague(&colors[key], multiplier, vague_hue)?),
        );
    }
    for key in [
        "surface",
        "surface_container_low",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
    ] {
        vague.insert(key.to_owned(), json!(cool_surface(&colors[key], vague_hue)?));
    }
    let on_surface = if light_mode { "#2d2b3d" } else { "#c8c6d1" };
    let on_surface_variant = if light_mode { "#5d5b6d" } else { "#b8b6c6" };
    for (key, value) in [
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
        ("on_primary_container", on_surface),
        ("outline", if light_mode { "#a0a0b8" } else { "#606079" }),
        (
            "outline_variant",
            if light_mode { "#78788c" } else { "#4a4a5e" },
        ),
    ] {
        vague.insert(key.to_owned(), json!(value));
    }
    for key in ["primary_container", "secondary_container", "tertiary_container"] {
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
