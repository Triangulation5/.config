use std::ffi::{c_char, c_int, c_void};
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

#[repr(C)]
#[derive(Default)]
struct NvmlUtilization {
    gpu: u32,
    memory: u32,
}

#[repr(C)]
#[derive(Default)]
struct NvmlMemory {
    total: u64,
    free: u64,
    used: u64,
}

const RTLD_LAZY: c_int = 1;
const SC_PAGESIZE: c_int = 30; // _SC_PAGESIZE on Linux
const NVML_TEMPERATURE_GPU: u32 = 0;

extern "C" {
    fn statvfs(path: *const c_char, buf: *mut Statvfs) -> c_int;
    fn sysconf(name: c_int) -> isize;
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

type NvmlInitFn = unsafe extern "C" fn() -> c_int;
type NvmlShutdownFn = unsafe extern "C" fn() -> c_int;
type NvmlGetHandleFn = unsafe extern "C" fn(u32, *mut *mut c_void) -> c_int;
type NvmlGetUtilFn = unsafe extern "C" fn(*mut c_void, *mut NvmlUtilization) -> c_int;
type NvmlGetTempFn = unsafe extern "C" fn(*mut c_void, u32, *mut u32) -> c_int;
type NvmlGetMemFn = unsafe extern "C" fn(*mut c_void, *mut NvmlMemory) -> c_int;

struct NvmlClient {
    lib: *mut c_void,
    device: *mut c_void,
    shutdown: NvmlShutdownFn,
    get_util: NvmlGetUtilFn,
    get_temp: NvmlGetTempFn,
    get_mem: NvmlGetMemFn,
}

impl NvmlClient {
    fn open() -> Option<Self> {
        unsafe {
            let lib = dlopen(b"libnvidia-ml.so.1\0".as_ptr() as *const c_char, RTLD_LAZY);
            if lib.is_null() {
                return None;
            }
            let init_sym = dlsym(lib, b"nvmlInit_v2\0".as_ptr() as *const c_char);
            let shutdown_sym = dlsym(lib, b"nvmlShutdown\0".as_ptr() as *const c_char);
            let handle_sym = dlsym(lib, b"nvmlDeviceGetHandleByIndex_v2\0".as_ptr() as *const c_char);
            let util_sym = dlsym(lib, b"nvmlDeviceGetUtilizationRates\0".as_ptr() as *const c_char);
            let temp_sym = dlsym(lib, b"nvmlDeviceGetTemperature\0".as_ptr() as *const c_char);
            let mem_sym = dlsym(lib, b"nvmlDeviceGetMemoryInfo\0".as_ptr() as *const c_char);

            if init_sym.is_null()
                || shutdown_sym.is_null()
                || handle_sym.is_null()
                || util_sym.is_null()
                || temp_sym.is_null()
                || mem_sym.is_null()
            {
                dlclose(lib);
                return None;
            }

            let init: NvmlInitFn = std::mem::transmute(init_sym);
            let shutdown: NvmlShutdownFn = std::mem::transmute(shutdown_sym);
            let get_handle: NvmlGetHandleFn = std::mem::transmute(handle_sym);
            let get_util: NvmlGetUtilFn = std::mem::transmute(util_sym);
            let get_temp: NvmlGetTempFn = std::mem::transmute(temp_sym);
            let get_mem: NvmlGetMemFn = std::mem::transmute(mem_sym);

            if init() != 0 {
                dlclose(lib);
                return None;
            }

            let mut device: *mut c_void = std::ptr::null_mut();
            if get_handle(0, &mut device) != 0 || device.is_null() {
                shutdown();
                dlclose(lib);
                return None;
            }

            Some(Self {
                lib,
                device,
                shutdown,
                get_util,
                get_temp,
                get_mem,
            })
        }
    }

    fn sample(&self) -> Option<(u32, u32, u64, u64)> {
        let mut util = NvmlUtilization::default();
        let mut temp: u32 = 0;
        let mut mem = NvmlMemory::default();
        unsafe {
            let u_ok = (self.get_util)(self.device, &mut util) == 0;
            let t_ok = (self.get_temp)(self.device, NVML_TEMPERATURE_GPU, &mut temp) == 0;
            let m_ok = (self.get_mem)(self.device, &mut mem) == 0;
            if !u_ok && !t_ok && !m_ok {
                return None;
            }
        }
        let used_mib = mem.used / (1024 * 1024);
        let total_mib = mem.total / (1024 * 1024);
        Some((util.gpu, temp, used_mib, total_mib))
    }
}

impl Drop for NvmlClient {
    fn drop(&mut self) {
        unsafe {
            (self.shutdown)();
            dlclose(self.lib);
        }
    }
}

fn page_size_bytes() -> u64 {
    let ps = unsafe { sysconf(SC_PAGESIZE) };
    if ps > 0 { ps as u64 } else { 4096 }
}

fn read_pid_rss_mb(pid: u32, page_size: u64) -> Option<u64> {
    let path = format!("/proc/{}/statm", pid);
    let content = fs::read_to_string(path).ok()?;
    let mut it = content.split_whitespace();
    let _total_pages = it.next()?;
    let rss_pages = it.next()?.parse::<u64>().ok()?;
    Some((rss_pages.saturating_mul(page_size)) / (1024 * 1024))
}

struct GpuInfo {
    vendor: &'static str,
    device_path: Option<PathBuf>,
    has_vram: bool,
    nvml: Option<NvmlClient>,
}

/// Priority of a temperature label across all hwmon devices. Lower is better.
/// Tdie (AMD CPU die) preferred, then Intel package, then AMD Tctl.
#[inline]
fn label_priority(label: &str) -> Option<u8> {
    match label {
        "Tdie" => Some(0),
        "Package id 0" => Some(1),
        "Tctl" => Some(2),
        _ => None,
    }
}

fn detect_cpu_temp() -> Option<PathBuf> {
    let hwmon_dir = Path::new("/sys/class/hwmon");
    let entries = fs::read_dir(hwmon_dir).ok()?;

    let hwmon_dirs: Vec<PathBuf> = entries
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_dir() || t.is_symlink()).unwrap_or(false))
        .map(|e| e.path())
        .collect();

    // Single pass over all devices: keep the best-priority labeled input found.
    // Falls back to any temp1_input as before.
    let mut best: Option<(u8, PathBuf)> = None;
    let mut fallback: Option<PathBuf> = None;
    for h in &hwmon_dirs {
        if let Ok(files) = fs::read_dir(h) {
            for f in files.flatten() {
                let name = f.file_name();
                let name_str = name.to_string_lossy();
                if !(name_str.starts_with("temp") && name_str.ends_with("_label")) {
                    continue;
                }
                if let Ok(label) = fs::read_to_string(f.path()) {
                    if let Some(prio) = label_priority(label.trim()) {
                        let input_name = name_str.replace("_label", "_input");
                        let input_path = h.join(input_name);
                        if input_path.exists() && best.as_ref().map_or(true, |(p, _)| prio < *p) {
                            best = Some((prio, input_path));
                            if prio == 0 {
                                return best.map(|(_, p)| p);
                            }
                        }
                    }
                }
            }
        }
        if fallback.is_none() {
            let input_path = h.join("temp1_input");
            if input_path.exists() {
                fallback = Some(input_path);
            }
        }
    }

    best.map(|(_, p)| p).or(fallback)
}

fn detect_gpu() -> GpuInfo {
    // Prefer native NVML (zero-fork) when available
    if let Some(nvml) = NvmlClient::open() {
        return GpuInfo {
            vendor: "nvidia",
            device_path: None,
            has_vram: true,
            nvml: Some(nvml),
        };
    }

    // Fallback to nvidia-smi CLI detection
    let nv_check = Command::new("nvidia-smi")
        .arg("-L")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();

    if let Ok(status) = nv_check {
        if status.success() {
            return GpuInfo {
                vendor: "nvidia",
                device_path: None,
                has_vram: true,
                nvml: None,
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
                            vendor: "amd",
                            device_path: Some(dev_path),
                            has_vram,
                            nvml: None,
                        };
                    }
                }
            }
        }
    }

    GpuInfo {
        vendor: "none",
        device_path: None,
        has_vram: false,
        nvml: None,
    }
}

fn read_proc_stat() -> Option<(u64, u64)> {
    let file = File::open("/proc/stat").ok()?;
    let reader = BufReader::new(file);
    for line in reader.lines().flatten() {
        if line.starts_with("cpu ") {
            let mut it = line.split_whitespace();
            let _ = it.next(); // "cpu"
            let user = it.next()?.parse::<u64>().unwrap_or(0);
            let nice = it.next()?.parse::<u64>().unwrap_or(0);
            let system = it.next()?.parse::<u64>().unwrap_or(0);
            let idle = it.next()?.parse::<u64>().unwrap_or(0);
            let iowait = it.next()?.parse::<u64>().unwrap_or(0);
            let irq = it.next()?.parse::<u64>().unwrap_or(0);
            let softirq = it.next()?.parse::<u64>().unwrap_or(0);
            let steal = it.next()?.parse::<u64>().unwrap_or(0);

            let total = user + nice + system + idle + iowait + irq + softirq + steal;
            let idle_total = idle + iowait;
            return Some((total, idle_total));
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
        // Split without allocating a Vec: interface token carries the colon.
        let mut it = line.split_whitespace();
        let dev = match it.next() {
            Some(d) => d.trim_end_matches(':'),
            None => continue,
        };
        if dev == "lo" {
            continue;
        }
        let rx: u64 = it.next().and_then(|s| s.parse().ok()).unwrap_or(0);
        // After rx bytes, the next 7 fields are rx counters, then tx bytes.
        let tx: u64 = it.nth(7).and_then(|s| s.parse().ok()).unwrap_or(0);
        rx_total += rx;
        tx_total += tx;
    }
    (rx_total, tx_total)
}

fn read_disk_pct() -> u32 {
    let mut st = Statvfs::default();
    let path = b"/\0";
    let res = unsafe { statvfs(path.as_ptr() as *const c_char, &mut st) };
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
    let vitals_only = args.iter().any(|a| a == "--vitals-only");

    let mut watch_pid: Option<u32> = None;
    let mut interval_ms: Option<u64> = None;
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--watch-pid" && i + 1 < args.len() {
            watch_pid = args[i + 1].parse::<u32>().ok();
            i += 2;
        } else if args[i] == "--interval" && i + 1 < args.len() {
            interval_ms = args[i + 1].parse::<u64>().ok();
            i += 2;
        } else {
            i += 1;
        }
    }

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

    if let Some(pid) = watch_pid {
        let sleep_dur = Duration::from_millis(interval_ms.unwrap_or(8000).max(500));
        let ps = page_size_bytes();
        loop {
            match read_pid_rss_mb(pid, ps) {
                Some(mb) => {
                    if writeln!(out, "RSS {}", mb).is_err() || out.flush().is_err() {
                        break;
                    }
                }
                None => break,
            }
            thread::sleep(sleep_dur);
        }
        return;
    }

    if vitals_only {
        let sleep_dur = Duration::from_millis(interval_ms.unwrap_or(2000).max(200));
        loop {
            if let Some((total, idle)) = read_proc_stat() {
                if writeln!(out, "CPU {} {}", total, idle).is_err() {
                    break;
                }
            }
            let (mt, ma, _, _) = read_proc_meminfo();
            if writeln!(out, "MEM {} {}", mt, ma).is_err() || out.flush().is_err() {
                break;
            }
            thread::sleep(sleep_dur);
        }
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
                if let Some(ref nvml) = gpu_info.nvml {
                    if let Some((gpu, temp, used_mib, total_mib)) = nvml.sample() {
                        let _ = writeln!(out, "GPU_NV {}, {}, {}, {}", gpu, temp, used_mib, total_mib);
                    }
                } else if let Ok(output) = Command::new("nvidia-smi")
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
