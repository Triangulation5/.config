use serde::Serialize;
use std::fs;

#[derive(Serialize)]
pub(crate) struct BacklightState {
    pub(crate) present: bool,
    pub(crate) pct: u32,
}

/// Read the first available `/sys/class/backlight/*` device directly without
/// spawning a shell.
pub(crate) fn read_backlight() -> BacklightState {
    let Ok(entries) = fs::read_dir("/sys/class/backlight") else {
        return BacklightState {
            present: false,
            pct: 0,
        };
    };

    let mut dirs: Vec<_> = entries.flatten().map(|e| e.path()).collect();
    dirs.sort();

    for dir in dirs {
        let Ok(max_str) = fs::read_to_string(dir.join("max_brightness")) else {
            continue;
        };
        let Ok(cur_str) = fs::read_to_string(dir.join("brightness")) else {
            continue;
        };
        let Ok(max) = max_str.trim().parse::<u64>() else {
            continue;
        };
        let Ok(cur) = cur_str.trim().parse::<u64>() else {
            continue;
        };
        if max == 0 {
            continue;
        }
        let pct = ((cur * 100) / max).clamp(1, 100) as u32;
        return BacklightState { present: true, pct };
    }

    BacklightState {
        present: false,
        pct: 0,
    }
}
