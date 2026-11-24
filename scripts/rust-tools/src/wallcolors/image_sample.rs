use super::color::{rgb_to_hls, Rgb};
use image::imageops::FilterType;
use sha1::{Digest, Sha1};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    time::UNIX_EPOCH,
};

type HueBucket = Option<(f64, Option<(f64, f64, f64)>)>;

struct HistogramAcc {
    buckets: [HueBucket; 12],
    total: u64,
    light_sum: f64,
    chroma: u64,
}

impl HistogramAcc {
    fn new() -> Self {
        Self {
            buckets: [None; 12],
            total: 0,
            light_sum: 0.0,
            chroma: 0,
        }
    }

    #[inline]
    fn add_sample(&mut self, count: u64, rgb: Rgb) {
        let (hue, lightness, saturation) = rgb_to_hls(rgb);
        self.total += count;
        self.light_sum += count as f64 * lightness;
        if saturation < 0.15 || !(0.05..=0.92).contains(&lightness) {
            return;
        }
        self.chroma += count;
        let bucket_index = ((hue * 360.0) as usize / 30) % 12;
        // SAFETY: `bucket_index` is modulo 12, so always in `0..12`.
        let slot = unsafe { self.buckets.get_unchecked_mut(bucket_index) };
        let bucket = slot.get_or_insert((0.0, None));
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

    fn finish(self) -> (Option<(f64, f64)>, f64) {
        let mean_lightness = if self.total > 0 {
            self.light_sum / self.total as f64
        } else {
            0.0
        };
        if self.total == 0 || (self.chroma as f64) < 0.08 * self.total as f64 {
            return (None, mean_lightness);
        }
        let winner = self
            .buckets
            .into_iter()
            .flatten()
            .reduce(|best, candidate| {
                if candidate.0 > best.0 {
                    candidate
                } else {
                    best
                }
            });
        let hue =
            winner.and_then(|(_, best)| best.map(|(_, hue, saturation)| (hue, saturation)));
        (hue, mean_lightness)
    }
}

/// Fast in-process histogram analysis via the `image` crate + unchecked 3-byte
/// RGB slice walk, falling back to ImageMagick only for unsupported formats.
pub(super) fn analyze(wallpaper: &Path) -> (Option<(f64, f64)>, f64) {
    if let Ok(decoded) = image::open(wallpaper) {
        let small = decoded.resize(200, 200, FilterType::Nearest).to_rgb8();
        let raw = small.as_raw();
        let mut acc = HistogramAcc::new();
        let triplets = raw.len() / 3;
        let ptr = raw.as_ptr();
        for i in 0..triplets {
            // SAFETY: `i < raw.len() / 3`, so `i * 3 + 2 < raw.len()`.
            let (r, g, b) = unsafe {
                let base = ptr.add(i * 3);
                (*base, *base.add(1), *base.add(2))
            };
            acc.add_sample(
                1,
                (
                    r as f64 * (1.0 / 255.0),
                    g as f64 * (1.0 / 255.0),
                    b as f64 * (1.0 / 255.0),
                ),
            );
        }
        return acc.finish();
    }

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

pub(super) fn analyze_histogram(output: &str) -> (Option<(f64, f64)>, f64) {
    let mut acc = HistogramAcc::new();
    for line in output.lines() {
        if let Some((count, rgb)) = parse_histogram_line(line) {
            acc.add_sample(count, rgb);
        }
    }
    acc.finish()
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
            ((parsed >> 16) & 0xff) as f64 * (1.0 / 255.0),
            ((parsed >> 8) & 0xff) as f64 * (1.0 / 255.0),
            (parsed & 0xff) as f64 * (1.0 / 255.0),
        ),
    ))
}

fn sample_pixels(image_path: &Path, size: u32) -> Vec<Rgb> {
    if let Ok(decoded) = image::open(image_path) {
        let resized = decoded
            .resize_exact(size, size, FilterType::Triangle)
            .to_rgb8();
        let raw = resized.as_raw();
        let triplets = raw.len() / 3;
        let ptr = raw.as_ptr();
        let mut out = Vec::with_capacity(triplets);
        for i in 0..triplets {
            // SAFETY: `i < raw.len() / 3`, so `i * 3 + 2 < raw.len()`.
            let (r, g, b) = unsafe {
                let base = ptr.add(i * 3);
                (*base, *base.add(1), *base.add(2))
            };
            out.push((
                r as f64 * (1.0 / 255.0),
                g as f64 * (1.0 / 255.0),
                b as f64 * (1.0 / 255.0),
            ));
        }
        return out;
    }

    let output = Command::new("magick")
        .arg(image_path)
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
                rgb[0] as f64 * (1.0 / 255.0),
                rgb[1] as f64 * (1.0 / 255.0),
                rgb[2] as f64 * (1.0 / 255.0),
            )
        })
        .collect()
}

pub(super) fn wallpaper_thumbnail(wallpaper: &Path, cache: &Path) -> PathBuf {
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

    let encoded_in_proc = image::open(wallpaper).ok().is_some_and(|decoded| {
        let small = decoded.resize_exact(128, 128, FilterType::Triangle).to_rgb8();
        small.save(&destination).is_ok()
    });
    if !encoded_in_proc {
        let made = Command::new("magick")
            .args(["-define", "jpeg:size=256x256"])
            .arg(wallpaper)
            .args(["-alpha", "off", "-resize", "128x128!"])
            .arg(&destination)
            .output();
        if !made.is_ok_and(|output| output.status.success()) {
            let _ = fs::remove_file(&destination);
            return wallpaper.to_path_buf();
        }
    }
    if !fs::metadata(&destination).is_ok_and(|metadata| metadata.len() > 0) {
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
        cached.sort_by_key(|left| left.0);
        let excess = cached.len().saturating_sub(128);
        for (_, stale) in cached.into_iter().take(excess) {
            let _ = fs::remove_file(stale);
        }
    }
    destination
}

pub(super) fn smart_mode_variant(image_path: &Path) -> (&'static str, &'static str) {
    let pixels = sample_pixels(image_path, 16);
    if pixels.is_empty() {
        return ("dark", "tonal-spot");
    }
    let count = pixels.len() as f64;
    let inv_n = 1.0 / count;
    let mut sum_r = 0.0;
    let mut sum_g = 0.0;
    let mut sum_b = 0.0;
    let mut sum_rg = 0.0;
    let mut sum_rg2 = 0.0;
    let mut sum_yb = 0.0;
    let mut sum_yb2 = 0.0;

    for &(r, g, b) in &pixels {
        sum_r += r;
        sum_g += g;
        sum_b += b;
        let rg = (r - g).abs();
        let yb = (0.5 * (r + g) - b).abs();
        sum_rg += rg;
        sum_rg2 += rg * rg;
        sum_yb += yb;
        sum_yb2 += yb * yb;
    }

    let red = sum_r * inv_n;
    let green = sum_g * inv_n;
    let blue = sum_b * inv_n;
    let lightness = (red.max(green).max(blue) + red.min(green).min(blue)) * 0.5;
    let mode = if lightness > 0.60 { "light" } else { "dark" };

    let mean_rg = sum_rg * inv_n;
    let mean_yb = sum_yb * inv_n;
    let var_rg = (sum_rg2 * inv_n - mean_rg * mean_rg).max(0.0);
    let var_yb = (sum_yb2 * inv_n - mean_yb * mean_yb).max(0.0);
    let colourfulness =
        (var_rg + var_yb).sqrt() + 0.3 * (mean_rg * mean_rg + mean_yb * mean_yb).sqrt();

    let variant = if colourfulness < 0.02 {
        "neutral"
    } else if colourfulness < 0.05 {
        "content"
    } else {
        "tonal-spot"
    };
    (mode, variant)
}
