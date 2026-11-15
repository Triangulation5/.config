use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[repr(C)]
#[derive(Default)]
struct Statvfs {
    f_bsize: usize,
    f_frsize: usize,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_favail: u64,
    f_fsid: usize,
    f_flag: usize,
    f_namemax: usize,
    __f_spare: [i32; 6],
}

extern "C" {
    fn statvfs(path: *const i8, buf: *mut Statvfs) -> i32;
}

struct GpuInfo {
    vendor: String,
    device_path: Option<PathBuf>,
    has_vram: bool,
}

fn detect_cpu_temp() -> Option<PathBuf> {
    let hwmon_dir = Path::new("/sys/class/hwmon");
    let entries = fs::read_dir(hwmon_dir).ok()?;

    let mut hwmon_dirs = Vec::new();
    for entry in entries.flatten() {
        if entry.file_type().map(|t| t.is_dir() || t.is_symlink()).unwrap_or(false) {
            hwmon_dirs.push(entry.path());
        }
    }

    // Pass 1: Tdie
    for h in &hwmon_dirs {
        if let Ok(files) = fs::read_dir(h) {
            for f in files.flatten() {
                let name = f.file_name();
                let name_str = name.to_string_lossy();
                if name_str.starts_with("temp") && name_str.ends_with("_label") {
                    if let Ok(label) = fs::read_to_string(f.path()) {
                        if label.trim() == "Tdie" {
                            let input_name = name_str.replace("_label", "_input");
                            let input_path = h.join(input_name);
                            if input_path.exists() {
                                return Some(input_path);
                            }
                        }
                    }
                }
            }
        }
    }

    // Pass 2: Package id 0
    for h in &hwmon_dirs {
        if let Ok(files) = fs::read_dir(h) {
            for f in files.flatten() {
                let name = f.file_name();
                let name_str = name.to_string_lossy();
                if name_str.starts_with("temp") && name_str.ends_with("_label") {
                    if let Ok(label) = fs::read_to_string(f.path()) {
                        if label.trim() == "Package id 0" {
                            let input_name = name_str.replace("_label", "_input");
                            let input_path = h.join(input_name);
                            if input_path.exists() {
                                return Some(input_path);
                            }
                        }
                    }
                }
            }
        }
    }

    // Pass 3: Tctl
    for h in &hwmon_dirs {
        if let Ok(files) = fs::read_dir(h) {
            for f in files.flatten() {
                let name = f.file_name();
                let name_str = name.to_string_lossy();
                if name_str.starts_with("temp") && name_str.ends_with("_label") {
                    if let Ok(label) = fs::read_to_string(f.path()) {
                        if label.trim() == "Tctl" {
                            let input_name = name_str.replace("_label", "_input");
                            let input_path = h.join(input_name);
                            if input_path.exists() {
                                return Some(input_path);
                            }
                        }
                    }
                }
            }
        }
    }

    // Pass 4: temp1_input
    for h in &hwmon_dirs {
        let input_path = h.join("temp1_input");
        if input_path.exists() {
            return Some(input_path);
        }
    }

    None
}

fn detect_gpu() -> GpuInfo {
    // Check nvidia-smi
    let nv_check = Command::new("nvidia-smi")
        .arg("-L")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();

    if let Ok(status) = nv_check {
        if status.success() {
            return GpuInfo {
                vendor: "nvidia".to_string(),
                device_path: None,
                has_vram: true,
            };
        }
    }

    // Check AMD DRM devices
    let drm_dir = Path::new("/sys/class/drm");
    if let Ok(entries) = fs::read_dir(drm_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with("card") && !name_str.contains('-') {
                let dev_path = entry.path().join("device");
                let vendor_file = dev_path.join("vendor");
                if let Ok(vendor) = fs::read_to_string(&vendor_file) {
                    if vendor.trim() == "0x1002" && dev_path.join("gpu_busy_percent").exists() {
                        let has_vram = dev_path.join("mem_info_vram_total").exists();
                        return GpuInfo {
                            vendor: "amd".to_string(),
                            device_path: Some(dev_path),
                            has_vram,
                        };
                    }
                }
            }
        }
    }

    GpuInfo {
        vendor: "none".to_string(),
        device_path: None,
        has_vram: false,
    }
}

fn read_proc_stat() -> Option<(u64, u64)> {
    let file = File::open("/proc/stat").ok()?;
    let reader = BufReader::new(file);
    for line in reader.lines().flatten() {
        if line.starts_with("cpu ") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 9 {
                let user: u64 = parts[1].parse().unwrap_or(0);
                let nice: u64 = parts[2].parse().unwrap_or(0);
                let system: u64 = parts[3].parse().unwrap_or(0);
                let idle: u64 = parts[4].parse().unwrap_or(0);
                let iowait: u64 = parts[5].parse().unwrap_or(0);
                let irq: u64 = parts[6].parse().unwrap_or(0);
                let softirq: u64 = parts[7].parse().unwrap_or(0);
                let steal: u64 = parts[8].parse().unwrap_or(0);

                let total = user + nice + system + idle + iowait + irq + softirq + steal;
                let idle_total = idle + iowait;
                return Some((total, idle_total));
            }
        }
    }
    None
}

fn read_proc_meminfo() -> (u64, u64, u64, u64) {
    let file = match File::open("/proc/meminfo") {
        Ok(f) => f,
        Err(_) => return (0, 0, 0, 0),
    };
    let reader = BufReader::new(file);
    let mut total = 0;
    let mut avail = 0;
    let mut swap_total = 0;
    let mut swap_free = 0;

    for line in reader.lines().flatten() {
        if line.starts_with("MemTotal:") {
            total = parse_kb(&line);
        } else if line.starts_with("MemAvailable:") {
            avail = parse_kb(&line);
        } else if line.starts_with("SwapTotal:") {
            swap_total = parse_kb(&line);
        } else if line.starts_with("SwapFree:") {
            swap_free = parse_kb(&line);
        }
    }
    (total, avail, swap_total, swap_free)
}

fn parse_kb(line: &str) -> u64 {
    let mut parts = line.split_whitespace();
    parts.next();
    parts.next().and_then(|v| v.parse().ok()).unwrap_or(0)
}

fn read_proc_net() -> (u64, u64) {
    let file = match File::open("/proc/net/dev") {
        Ok(f) => f,
        Err(_) => return (0, 0),
    };
    let reader = BufReader::new(file);
    let mut rx_total = 0;
    let mut tx_total = 0;

    for (i, line) in reader.lines().flatten().enumerate() {
        if i < 2 {
            continue;
        }
        let clean = line.replace(':', " ");
        let parts: Vec<&str> = clean.split_whitespace().collect();
        if parts.is_empty() || parts[0] == "lo" {
            continue;
        }
        if parts.len() >= 10 {
            let rx: u64 = parts[1].parse().unwrap_or(0);
            let tx: u64 = parts[9].parse().unwrap_or(0);
            rx_total += rx;
            tx_total += tx;
        }
    }
    (rx_total, tx_total)
}

fn read_disk_pct() -> u32 {
    let mut st = Statvfs::default();
    let path = b"/\0";
    let res = unsafe { statvfs(path.as_ptr() as *const i8, &mut st) };
    if res == 0 && st.f_blocks > 0 {
        let used = st.f_blocks.saturating_sub(st.f_bavail);
        ((used as f64 / st.f_blocks as f64) * 100.0).round() as u32
    } else {
        0
    }
}

fn read_uptime() -> u64 {
    if let Ok(content) = fs::read_to_string("/proc/uptime") {
        if let Some(first) = content.split_whitespace().next() {
            if let Ok(secs) = first.parse::<f64>() {
                return secs.floor() as u64;
            }
        }
    }
    0
}

fn sample_amd_gpu(dev: &Path) -> (u32, i32, u64, u64) {
    let busy = fs::read_to_string(dev.join("gpu_busy_percent"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    let mut temp = 0;
    if let Ok(hwmon_entries) = fs::read_dir(dev.join("hwmon")) {
        for h in hwmon_entries.flatten() {
            if let Ok(t) = fs::read_to_string(h.path().join("temp1_input")) {
                temp = t.trim().parse().unwrap_or(0);
                break;
            }
        }
    }

    let vu = fs::read_to_string(dev.join("mem_info_vram_used"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    let vt = fs::read_to_string(dev.join("mem_info_vram_total"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    (busy, temp, vu, vt)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let detect_only = args.iter().any(|a| a == "--detect-only");
    let once = args.iter().any(|a| a == "--once");

    let stdout = io::stdout();
    let mut out = stdout.lock();

    if once {
        if let Some((total, idle)) = read_proc_stat() {
            let _ = writeln!(out, "CPU {} {}", total, idle);
        }
        let (mt, ma, _, _) = read_proc_meminfo();
        let _ = writeln!(out, "MEM {} {}", mt, ma);
        let _ = out.flush();
        return;
    }

    let temp_path = detect_cpu_temp();
    let gpu_info = detect_gpu();

    // Emit detection results
    if let Some(ref p) = temp_path {
        let _ = writeln!(out, "DETECT TEMP {}", p.display());
    } else {
        let _ = writeln!(out, "DETECT TEMP -");
    }

    if gpu_info.vendor == "amd" {
        let dev_str = gpu_info.device_path.as_ref().map(|p| p.display().to_string()).unwrap_or_default();
        let _ = writeln!(out, "DETECT GPU amd {} {}", dev_str, if gpu_info.has_vram { "1" } else { "0" });
    } else if gpu_info.vendor == "nvidia" {
        let _ = writeln!(out, "DETECT GPU nvidia");
    } else {
        let _ = writeln!(out, "DETECT GPU none");
    }
    let _ = out.flush();

    if detect_only {
        return;
    }

    let mut tick: u64 = 0;

    loop {
        // Fast metrics (1s)
        if let Some((total, idle)) = read_proc_stat() {
            let _ = writeln!(out, "CPU {} {}", total, idle);
        }

        let (mt, ma, st, sf) = read_proc_meminfo();
        let _ = writeln!(out, "MEM {} {} {} {}", mt, ma, st, sf);

        let (rx, tx) = read_proc_net();
        let _ = writeln!(out, "NET {} {}", rx, tx);

        if let Some(ref p) = temp_path {
            if let Ok(s) = fs::read_to_string(p) {
                let _ = writeln!(out, "TMP {}", s.trim());
            } else {
                let _ = writeln!(out, "TMP -");
            }
        } else {
            let _ = writeln!(out, "TMP -");
        }

        // GPU metrics (2s)
        if tick % 2 == 0 {
            if gpu_info.vendor == "nvidia" {
                if let Ok(output) = Command::new("nvidia-smi")
                    .args(["--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"])
                    .output()
                {
                    if let Some(first_line) = String::from_utf8_lossy(&output.stdout).lines().next() {
                        let _ = writeln!(out, "GPU_NV {}", first_line.trim());
                    }
                }
            } else if gpu_info.vendor == "amd" {
                if let Some(ref dev) = gpu_info.device_path {
                    let (busy, temp, vu, vt) = sample_amd_gpu(dev);
                    let _ = writeln!(out, "GPU_AMD {} {} {} {}", busy, temp, vu, vt);
                }
            }
        }

        // Slow metrics (5s, plus on tick 0 for instant initial values)
        if tick % 5 == 0 {
            let disk = read_disk_pct();
            let _ = writeln!(out, "DISK {}", disk);

            let up = read_uptime();
            let _ = writeln!(out, "UP {}", up);
        }

        if out.flush().is_err() {
            // Receiver pipe closed, exit cleanly
            break;
        }

        tick = tick.wrapping_add(1);
        thread::sleep(Duration::from_secs(1));
    }
}
