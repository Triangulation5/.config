use std::cmp::Ordering;

pub(super) type Rgb = (f64, f64, f64);

const INVALID_HEX: u8 = 0xFF;

const HEX_LUT: [u8; 256] = {
    let mut lut = [INVALID_HEX; 256];
    let mut i = b'0';
    while i <= b'9' {
        lut[i as usize] = i - b'0';
        i += 1;
    }
    let mut i = b'a';
    while i <= b'f' {
        lut[i as usize] = i - b'a' + 10;
        i += 1;
    }
    let mut i = b'A';
    while i <= b'F' {
        lut[i as usize] = i - b'A' + 10;
        i += 1;
    }
    lut
};

const HEX_DIGITS: &[u8; 16] = b"0123456789abcdef";

#[inline]
pub(super) fn parse_hex(color: &str) -> Result<Rgb, String> {
    let bytes = color.as_bytes();
    let hex = if !bytes.is_empty() && bytes[0] == b'#' {
        &bytes[1..]
    } else {
        bytes
    };
    if hex.len() != 6 {
        return Err(format!("invalid color: {color}"));
    }
    // SAFETY: `hex.len() == 6` is checked above, and every `u8` index `0..256`
    // is in-bounds for the 256-entry `HEX_LUT` table.
    let (r_hi, r_lo, g_hi, g_lo, b_hi, b_lo) = unsafe {
        (
            *HEX_LUT.get_unchecked(*hex.get_unchecked(0) as usize),
            *HEX_LUT.get_unchecked(*hex.get_unchecked(1) as usize),
            *HEX_LUT.get_unchecked(*hex.get_unchecked(2) as usize),
            *HEX_LUT.get_unchecked(*hex.get_unchecked(3) as usize),
            *HEX_LUT.get_unchecked(*hex.get_unchecked(4) as usize),
            *HEX_LUT.get_unchecked(*hex.get_unchecked(5) as usize),
        )
    };
    if (r_hi | r_lo | g_hi | g_lo | b_hi | b_lo) == INVALID_HEX {
        return Err(format!("invalid color: {color}"));
    }
    let r = (r_hi << 4) | r_lo;
    let g = (g_hi << 4) | g_lo;
    let b = (b_hi << 4) | b_lo;
    Ok((
        r as f64 * (1.0 / 255.0),
        g as f64 * (1.0 / 255.0),
        b as f64 * (1.0 / 255.0),
    ))
}

#[inline]
pub(super) fn rgb_to_hls((red, green, blue): Rgb) -> (f64, f64, f64) {
    let max = red.max(green).max(blue);
    let min = red.min(green).min(blue);
    let lightness = (max + min) * 0.5;
    if max == min {
        return (0.0, lightness, 0.0);
    }
    let delta = max - min;
    let saturation = if lightness <= 0.5 {
        delta / (max + min)
    } else {
        delta / (2.0 - max - min)
    };
    let inv_delta = 1.0 / delta;
    let red_delta = (max - red) * inv_delta;
    let green_delta = (max - green) * inv_delta;
    let blue_delta = (max - blue) * inv_delta;
    let hue = if red == max {
        blue_delta - green_delta
    } else if green == max {
        2.0 + red_delta - blue_delta
    } else {
        4.0 + green_delta - red_delta
    };
    ((hue / 6.0).rem_euclid(1.0), lightness, saturation)
}

#[inline]
pub(super) fn hls_to_rgb(hue: f64, lightness: f64, saturation: f64) -> Rgb {
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
    let h = hue.rem_euclid(1.0);
    (
        hue_to_rgb(m1, m2, h + 1.0 / 3.0),
        hue_to_rgb(m1, m2, h),
        hue_to_rgb(m1, m2, h - 1.0 / 3.0),
    )
}

#[inline]
fn hue_to_rgb(m1: f64, m2: f64, mut hue: f64) -> f64 {
    if hue < 0.0 {
        hue += 1.0;
    } else if hue > 1.0 {
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

#[inline]
pub(super) fn hsl_hex(hue: f64, saturation: f64, lightness: f64) -> String {
    rgb_hex(hls_to_rgb(
        hue,
        lightness.clamp(0.0, 1.0),
        saturation.clamp(0.0, 1.0),
    ))
}

#[inline]
pub(super) fn rgb_hex((red, green, blue): Rgb) -> String {
    let r = py_round(red * 255.0) as usize;
    let g = py_round(green * 255.0) as usize;
    let b = py_round(blue * 255.0) as usize;
    // SAFETY: `r`, `g`, `b` are `u8` values (`0..=255`), so `>> 4` and `& 0x0F`
    // are in `0..16`, and all 7 bytes are valid ASCII (`'#'` + `'0'..='f'`).
    unsafe {
        let buf = vec![
            b'#',
            *HEX_DIGITS.get_unchecked(r >> 4),
            *HEX_DIGITS.get_unchecked(r & 0x0F),
            *HEX_DIGITS.get_unchecked(g >> 4),
            *HEX_DIGITS.get_unchecked(g & 0x0F),
            *HEX_DIGITS.get_unchecked(b >> 4),
            *HEX_DIGITS.get_unchecked(b & 0x0F),
        ];
        String::from_utf8_unchecked(buf)
    }
}

#[inline]
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

#[inline]
pub(super) fn tint(hue: f64, saturation: f64, lightness: f64) -> String {
    hsl_hex(hue, saturation, lightness)
}

#[inline]
pub(super) fn lerp(value: f64, start: f64, end: f64, low: f64, high: f64) -> f64 {
    let amount = ((value - start) / (end - start)).clamp(0.0, 1.0);
    low + amount * (high - low)
}

pub(super) fn mix_hex(first: &str, second: &str, amount: f64) -> Result<String, String> {
    let first = parse_hex(first)?;
    let second = parse_hex(second)?;
    Ok(rgb_hex((
        first.0 + (second.0 - first.0) * amount,
        first.1 + (second.1 - first.1) * amount,
        first.2 + (second.2 - first.2) * amount,
    )))
}

pub(super) fn is_light(color: &str) -> Result<bool, String> {
    let (red, green, blue) = parse_hex(color)?;
    Ok(0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.5)
}

pub(super) fn hex_hls(color: &str) -> Result<(f64, f64, f64), String> {
    Ok(rgb_to_hls(parse_hex(color)?))
}

pub(super) fn with_lightness(color: &str, lightness: f64) -> Result<String, String> {
    let (hue, _, saturation) = hex_hls(color)?;
    Ok(hsl_hex(hue, saturation, lightness.clamp(0.02, 0.98)))
}

pub(super) fn scale_saturation(color: &str, amount: f64) -> Result<String, String> {
    let (hue, lightness, saturation) = hex_hls(color)?;
    Ok(hsl_hex(
        hue,
        (saturation * amount).clamp(0.0, 1.0),
        lightness,
    ))
}

#[inline]
pub(super) fn relative_luminance(color: &str) -> Result<f64, String> {
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

#[inline]
pub(super) fn contrast_ratio(first: &str, second: &str) -> Result<f64, String> {
    let first = relative_luminance(first)?;
    let second = relative_luminance(second)?;
    let (light, dark) = if first >= second {
        (first, second)
    } else {
        (second, first)
    };
    Ok((light + 0.05) / (dark + 0.05))
}

pub(super) fn best_extreme(backgrounds: &[String]) -> Result<String, String> {
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

fn meets_contrast(ink: &str, backgrounds: &[String], target: f64) -> Result<bool, String> {
    for bg in backgrounds {
        if contrast_ratio(ink, bg)? < target {
            return Ok(false);
        }
    }
    Ok(true)
}

pub(super) fn walk_ink(ink: &str, backgrounds: &[String], target: f64) -> Result<String, String> {
    if meets_contrast(ink, backgrounds, target)? {
        return Ok(ink.to_owned());
    }
    let extreme = best_extreme(backgrounds)?;
    for amount in [0.12, 0.24, 0.36, 0.48, 0.6, 0.75, 0.9, 1.0] {
        let candidate = mix_hex(ink, &extreme, amount)?;
        if meets_contrast(&candidate, backgrounds, target)? {
            return Ok(candidate);
        }
    }
    Ok(extreme)
}
