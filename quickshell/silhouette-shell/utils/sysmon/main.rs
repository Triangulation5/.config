mod nvml;
mod proc;

use nvml::{detect_gpu, sample_amd_gpu};
use proc::{
    detect_cpu_temp, page_size_bytes, parse_proc_meminfo, parse_proc_net, parse_proc_stat,
    parse_statm_rss_mb, parse_uptime, read_disk_pct, read_proc_meminfo, read_proc_stat,
    ReusableReader,
};
use std::ffi::c_int;
use std::io::{self, Write};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

const SIGHUP: c_int = 1;

static RESCAN_TEMP: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_sighup(_sig: c_int) {
    RESCAN_TEMP.store(true, Ordering::Relaxed);
}

extern "C" {
    fn signal(sig: c_int, handler: usize) -> usize;
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
        let mut statm = ReusableReader::open(format!("/proc/{}/statm", pid), 64);
        while let Some(mb) = statm.read().and_then(|s| parse_statm_rss_mb(s, ps)) {
            if writeln!(out, "RSS {}", mb).is_err() || out.flush().is_err() {
                break;
            }
            thread::sleep(sleep_dur);
        }
        return;
    }

    if vitals_only {
        let sleep_dur = Duration::from_millis(interval_ms.unwrap_or(2000).max(200));
        let mut stat_r = ReusableReader::open("/proc/stat", 4096);
        let mut mem_r = ReusableReader::open("/proc/meminfo", 2048);
        loop {
            if let Some((total, idle)) = stat_r.read().and_then(parse_proc_stat) {
                if writeln!(out, "CPU {} {}", total, idle).is_err() {
                    break;
                }
            }
            let (mt, ma, _, _) = mem_r.read().map_or((0, 0, 0, 0), parse_proc_meminfo);
            if writeln!(out, "MEM {} {}", mt, ma).is_err() || out.flush().is_err() {
                break;
            }
            thread::sleep(sleep_dur);
        }
        return;
    }

    let mut temp_path = detect_cpu_temp();
    let gpu_info = detect_gpu();

    if let Some(ref p) = temp_path {
        let _ = writeln!(out, "DETECT TEMP {}", p.display());
    } else {
        let _ = writeln!(out, "DETECT TEMP -");
    }

    if gpu_info.vendor == "amd" {
        let dev_str = gpu_info
            .device_path
            .as_ref()
            .map(|p| p.display().to_string())
            .unwrap_or_default();
        let _ = writeln!(
            out,
            "DETECT GPU amd {} {}",
            dev_str,
            if gpu_info.has_vram { "1" } else { "0" }
        );
    } else if gpu_info.vendor == "nvidia" {
        let _ = writeln!(out, "DETECT GPU nvidia");
    } else {
        let _ = writeln!(out, "DETECT GPU none");
    }
    let _ = out.flush();

    if detect_only {
        return;
    }

    unsafe {
        signal(SIGHUP, handle_sighup as *const () as usize);
    }

    let mut stat_r = ReusableReader::open("/proc/stat", 4096);
    let mut mem_r = ReusableReader::open("/proc/meminfo", 2048);
    let mut net_r = ReusableReader::open("/proc/net/dev", 2048);
    let mut uptime_r = ReusableReader::open("/proc/uptime", 64);
    let mut temp_r = temp_path.as_ref().map(|p| ReusableReader::open(p, 32));
    let mut tick: u64 = 0;

    loop {
        if RESCAN_TEMP.swap(false, Ordering::Relaxed) || (tick > 0 && tick.is_multiple_of(150)) {
            temp_path = detect_cpu_temp();
            temp_r = temp_path.as_ref().map(|p| ReusableReader::open(p, 32));
        }

        if let Some((total, idle)) = stat_r.read().and_then(parse_proc_stat) {
            let _ = writeln!(out, "CPU {} {}", total, idle);
        }

        let (mt, ma, st, sf) = mem_r.read().map_or((0, 0, 0, 0), parse_proc_meminfo);
        let _ = writeln!(out, "MEM {} {} {} {}", mt, ma, st, sf);

        let (rx, tx) = net_r.read().map_or((0, 0), parse_proc_net);
        let _ = writeln!(out, "NET {} {}", rx, tx);

        if let Some(ref mut tr) = temp_r {
            if let Some(s) = tr.read() {
                let _ = writeln!(out, "TMP {}", s.trim());
            } else {
                let _ = writeln!(out, "TMP -");
            }
        } else {
            let _ = writeln!(out, "TMP -");
        }

        if gpu_info.vendor == "nvidia" {
            if let Some(ref nvml) = gpu_info.nvml {
                if let Some((gpu, temp, used_mib, total_mib)) = nvml.sample() {
                    let _ = writeln!(out, "GPU_NV {}, {}, {}, {}", gpu, temp, used_mib, total_mib);
                }
            } else if let Ok(output) = Command::new("nvidia-smi")
                .args([
                    "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                    "--format=csv,noheader,nounits",
                ])
                .output()
            {
                if let Some(first_line) = String::from_utf8_lossy(&output.stdout).lines().next() {
                    let _ = writeln!(out, "GPU_NV {}", first_line.trim());
                }
            }
        } else if gpu_info.vendor == "amd" {
            if let Some(ref dev) = gpu_info.device_path {
                let (busy, temp, vu, vt) = sample_amd_gpu(dev, gpu_info.amd_temp_path.as_deref());
                let _ = writeln!(out, "GPU_AMD {} {} {} {}", busy, temp, vu, vt);
            }
        }

        if tick.is_multiple_of(15) {
            let disk = read_disk_pct();
            let _ = writeln!(out, "DISK {}", disk);

            let up = uptime_r.read().map_or(0, parse_uptime);
            let _ = writeln!(out, "UP {}", up);
        }

        if out.flush().is_err() {
            break;
        }

        tick = tick.wrapping_add(1);
        thread::sleep(Duration::from_secs(2));
    }
}
