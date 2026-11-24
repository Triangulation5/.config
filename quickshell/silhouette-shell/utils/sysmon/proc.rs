use std::ffi::{c_char, c_int};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

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

const PAGE_SIZE: u64 = 4096;
#[cfg(not(target_arch = "x86_64"))]
const SC_PAGESIZE: c_int = 30;

extern "C" {
    fn statvfs(path: *const c_char, buf: *mut Statvfs) -> c_int;
    #[cfg(not(target_arch = "x86_64"))]
    fn sysconf(name: c_int) -> isize;
}

/// Keeps a `/proc` or `/sys` file descriptor open and reads into a reusable
/// `String` buffer via `seek(0)` to avoid repeated `open`/`close` and allocations.
pub(crate) struct ReusableReader {
    file: Option<File>,
    buf: String,
}

impl ReusableReader {
    pub(crate) fn open(path: impl AsRef<Path>, cap: usize) -> Self {
        Self {
            file: File::open(path).ok(),
            buf: String::with_capacity(cap),
        }
    }

    pub(crate) fn read(&mut self) -> Option<&str> {
        let f = self.file.as_mut()?;
        f.seek(SeekFrom::Start(0)).ok()?;
        self.buf.clear();
        f.read_to_string(&mut self.buf).ok()?;
        Some(&self.buf)
    }
}

#[inline]
pub(crate) fn page_size_bytes() -> u64 {
    #[cfg(target_arch = "x86_64")]
    {
        PAGE_SIZE
    }
    #[cfg(not(target_arch = "x86_64"))]
    {
        let ps = unsafe { sysconf(SC_PAGESIZE) };
        if ps > 0 { ps as u64 } else { PAGE_SIZE }
    }
}

pub(crate) fn parse_statm_rss_mb(content: &str, page_size: u64) -> Option<u64> {
    let mut it = content.split_whitespace();
    let _total_pages = it.next()?;
    let rss_pages = it.next()?.parse::<u64>().ok()?;
    Some((rss_pages.saturating_mul(page_size)) / (1024 * 1024))
}

#[cfg(test)]
fn read_pid_rss_mb(pid: u32, page_size: u64) -> Option<u64> {
    let path = format!("/proc/{}/statm", pid);
    let content = fs::read_to_string(path).ok()?;
    parse_statm_rss_mb(&content, page_size)
}

/// Priority of a temperature label across all hwmon devices. Lower is better.
#[inline]
pub(crate) fn label_priority(label: &str) -> Option<u8> {
    match label {
        "Tdie" => Some(0),
        "Package id 0" => Some(1),
        "Tctl" => Some(2),
        _ => None,
    }
}

pub(crate) fn detect_cpu_temp() -> Option<PathBuf> {
    let hwmon_dir = Path::new("/sys/class/hwmon");
    let entries = fs::read_dir(hwmon_dir).ok()?;

    let hwmon_dirs: Vec<PathBuf> = entries
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_dir() || t.is_symlink()).unwrap_or(false))
        .map(|e| e.path())
        .collect();

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
                        if input_path.exists() && best.as_ref().is_none_or(|(p, _)| prio < *p) {
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

pub(crate) fn parse_proc_stat(content: &str) -> Option<(u64, u64)> {
    for line in content.lines() {
        if line.starts_with("cpu ") {
            let mut it = line.split_whitespace();
            let _ = it.next();
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

pub(crate) fn read_proc_stat() -> Option<(u64, u64)> {
    let content = fs::read_to_string("/proc/stat").ok()?;
    parse_proc_stat(&content)
}

#[inline]
fn parse_kb(line: &str) -> u64 {
    let mut parts = line.split_whitespace();
    parts.next();
    parts.next().and_then(|v| v.parse().ok()).unwrap_or(0)
}

pub(crate) fn parse_proc_meminfo(content: &str) -> (u64, u64, u64, u64) {
    let (mut total, mut avail, mut swap_total, mut swap_free) = (0, 0, 0, 0);
    for line in content.lines() {
        if line.starts_with("MemTotal:") {
            total = parse_kb(line);
        } else if line.starts_with("MemAvailable:") {
            avail = parse_kb(line);
        } else if line.starts_with("SwapTotal:") {
            swap_total = parse_kb(line);
        } else if line.starts_with("SwapFree:") {
            swap_free = parse_kb(line);
        }
    }
    (total, avail, swap_total, swap_free)
}

pub(crate) fn read_proc_meminfo() -> (u64, u64, u64, u64) {
    match fs::read_to_string("/proc/meminfo") {
        Ok(content) => parse_proc_meminfo(&content),
        Err(_) => (0, 0, 0, 0),
    }
}

pub(crate) fn parse_proc_net(content: &str) -> (u64, u64) {
    let (mut rx_total, mut tx_total) = (0, 0);
    for (i, line) in content.lines().enumerate() {
        if i < 2 {
            continue;
        }
        let mut it = line.split_whitespace();
        let dev = match it.next() {
            Some(d) => d.trim_end_matches(':'),
            None => continue,
        };
        if dev == "lo" {
            continue;
        }
        let rx: u64 = it.next().and_then(|s| s.parse().ok()).unwrap_or(0);
        let tx: u64 = it.nth(7).and_then(|s| s.parse().ok()).unwrap_or(0);
        rx_total += rx;
        tx_total += tx;
    }
    (rx_total, tx_total)
}

pub(crate) fn read_disk_pct() -> u32 {
    let mut st = Statvfs::default();
    let res = unsafe { statvfs(c"/".as_ptr(), &mut st) };
    if res == 0 && st.f_blocks > 0 {
        let used = st.f_blocks.saturating_sub(st.f_bavail);
        ((used as f64 / st.f_blocks as f64) * 100.0).round() as u32
    } else {
        0
    }
}

pub(crate) fn parse_uptime(content: &str) -> u64 {
    if let Some(first) = content.split_whitespace().next() {
        if let Ok(secs) = first.parse::<f64>() {
            return secs.floor() as u64;
        }
    }
    0
}

#[cfg(test)]
fn read_uptime() -> u64 {
    fs::read_to_string("/proc/uptime")
        .map(|c| parse_uptime(&c))
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temp_label_priorities() {
        assert_eq!(label_priority("Tdie"), Some(0));
        assert_eq!(label_priority("Package id 0"), Some(1));
        assert_eq!(label_priority("Tctl"), Some(2));
        assert_eq!(label_priority("Composite"), None);
    }

    #[test]
    fn proc_readers_return_sane_values() {
        let (total, idle) = read_proc_stat().expect("proc/stat readable");
        assert!(total > 0 && total >= idle);

        let (mt, ma, _st, _sf) = read_proc_meminfo();
        assert!(mt > 0 && ma <= mt);

        let disk = read_disk_pct();
        assert!(disk <= 100);

        let up = read_uptime();
        assert!(up > 0);
    }

    #[test]
    fn pid_rss_self_and_missing() {
        let ps = page_size_bytes();
        assert!(ps >= 4096 && ps.is_power_of_two());
        let self_rss = read_pid_rss_mb(std::process::id(), ps);
        assert!(self_rss.is_some());
        assert_eq!(read_pid_rss_mb(u32::MAX, ps), None);
    }
}
