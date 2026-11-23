use std::ffi::{c_char, c_int, c_long, c_uint, c_void, CString};
use std::io::{self, Write};
use std::ptr;
use std::time::{Duration, Instant};

const AF_INET: u16 = 2;
const IFF_UP: c_uint = 0x1;
const IFF_LOOPBACK: c_uint = 0x8;

#[repr(C)]
struct SockAddr {
    sa_family: u16,
    sa_data: [u8; 14],
}

#[repr(C)]
struct IfAddrs {
    ifa_next: *mut IfAddrs,
    ifa_name: *mut c_char,
    ifa_flags: c_uint,
    ifa_addr: *mut SockAddr,
    ifa_netmask: *mut SockAddr,
    ifa_ifu: *mut SockAddr,
    ifa_data: *mut c_void,
}

extern "C" {
    fn getifaddrs(ifap: *mut *mut IfAddrs) -> c_int;
    fn freeifaddrs(ifa: *mut IfAddrs);
}

/// Prints the first active global IPv4 address via `getifaddrs()` (replaces `sh | ip | awk | cut`).
pub fn cmd_net_local_ip() {
    unsafe {
        let mut head: *mut IfAddrs = ptr::null_mut();
        if getifaddrs(&mut head) != 0 || head.is_null() {
            return;
        }
        let mut cur = head;
        while !cur.is_null() {
            let ifa = &*cur;
            let up = (ifa.ifa_flags & IFF_UP) != 0;
            let loopback = (ifa.ifa_flags & IFF_LOOPBACK) != 0;
            if up && !loopback && !ifa.ifa_addr.is_null() {
                let sa = &*ifa.ifa_addr;
                if sa.sa_family == AF_INET {
                    // sockaddr_in: sa_data[0..2] = sin_port, sa_data[2..6] = sin_addr
                    let a = sa.sa_data[2];
                    let b = sa.sa_data[3];
                    let c = sa.sa_data[4];
                    let d = sa.sa_data[5];
                    // Skip loopback 127.0.0.0/8 and link-local 169.254.0.0/16
                    if a != 127 && !(a == 169 && b == 254) {
                        println!("{}.{}.{}.{}", a, b, c, d);
                        break;
                    }
                }
            }
            cur = ifa.ifa_next;
        }
        freeifaddrs(head);
    }
}

const RTLD_LAZY: c_int = 1;

// libcurl option constants (stable ABI across all libcurl 7/8 releases)
const CURLOPT_WRITEDATA: c_int = 10001;
const CURLOPT_URL: c_int = 10002;
const CURLOPT_READDATA: c_int = 10009;
const CURLOPT_TIMEOUT: c_int = 13;
const CURLOPT_POST: c_int = 47;
const CURLOPT_FOLLOWLOCATION: c_int = 52;
const CURLOPT_NOSIGNAL: c_int = 99;
const CURLOPT_POSTFIELDSIZE_LARGE: c_int = 30120;
const CURLOPT_WRITEFUNCTION: c_int = 20011;
const CURLOPT_READFUNCTION: c_int = 20012;
const CURLOPT_DOH_URL: c_int = 10282;

const CURLINFO_RESPONSE_CODE: c_int = 0x200000 + 2;

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

type CurlGlobalInitFn = unsafe extern "C" fn(c_long) -> c_int;
type CurlEasyInitFn = unsafe extern "C" fn() -> *mut c_void;
type CurlEasyCleanupFn = unsafe extern "C" fn(*mut c_void);
type CurlEasyPerformFn = unsafe extern "C" fn(*mut c_void) -> c_int;
type CurlEasySetoptPtrFn = unsafe extern "C" fn(*mut c_void, c_int, *const c_void) -> c_int;
type CurlEasySetoptLongFn = unsafe extern "C" fn(*mut c_void, c_int, c_long) -> c_int;
type CurlEasySetoptI64Fn = unsafe extern "C" fn(*mut c_void, c_int, i64) -> c_int;
type CurlEasyGetinfoLongFn = unsafe extern "C" fn(*mut c_void, c_int, *mut c_long) -> c_int;

type WriteCallback = unsafe extern "C" fn(*const c_char, usize, usize, *mut c_void) -> usize;
type ReadCallback = unsafe extern "C" fn(*mut c_char, usize, usize, *mut c_void) -> usize;

struct LibCurl {
    lib: *mut c_void,
    easy_init: CurlEasyInitFn,
    easy_cleanup: CurlEasyCleanupFn,
    easy_perform: CurlEasyPerformFn,
    setopt_ptr: CurlEasySetoptPtrFn,
    setopt_long: CurlEasySetoptLongFn,
    setopt_i64: CurlEasySetoptI64Fn,
    getinfo_long: CurlEasyGetinfoLongFn,
}

impl LibCurl {
    fn load() -> Option<Self> {
        unsafe {
            let lib = dlopen(b"libcurl.so.4\0".as_ptr() as *const c_char, RTLD_LAZY);
            if lib.is_null() {
                return None;
            }
            let global_init_p = dlsym(lib, b"curl_global_init\0".as_ptr() as *const c_char);
            let easy_init_p = dlsym(lib, b"curl_easy_init\0".as_ptr() as *const c_char);
            let easy_cleanup_p = dlsym(lib, b"curl_easy_cleanup\0".as_ptr() as *const c_char);
            let easy_perform_p = dlsym(lib, b"curl_easy_perform\0".as_ptr() as *const c_char);
            let setopt_p = dlsym(lib, b"curl_easy_setopt\0".as_ptr() as *const c_char);
            let getinfo_p = dlsym(lib, b"curl_easy_getinfo\0".as_ptr() as *const c_char);
            if global_init_p.is_null()
                || easy_init_p.is_null()
                || easy_cleanup_p.is_null()
                || easy_perform_p.is_null()
                || setopt_p.is_null()
                || getinfo_p.is_null()
            {
                dlclose(lib);
                return None;
            }
            let global_init: CurlGlobalInitFn = std::mem::transmute(global_init_p);
            let _ = global_init(3); // CURL_GLOBAL_DEFAULT
            Some(Self {
                lib,
                easy_init: std::mem::transmute(easy_init_p),
                easy_cleanup: std::mem::transmute(easy_cleanup_p),
                easy_perform: std::mem::transmute(easy_perform_p),
                setopt_ptr: std::mem::transmute(setopt_p),
                setopt_long: std::mem::transmute(setopt_p),
                setopt_i64: std::mem::transmute(setopt_p),
                getinfo_long: std::mem::transmute(getinfo_p),
            })
        }
    }

    fn get_bytes(&self, url: &str, timeout_secs: c_long, doh_url: Option<&str>) -> Result<(c_long, Vec<u8>), c_int> {
        let c_url = CString::new(url).map_err(|_| -1)?;
        let c_doh = match doh_url {
            Some(d) => Some(CString::new(d).map_err(|_| -1)?),
            None => None,
        };
        let mut body: Vec<u8> = Vec::new();
        unsafe {
            let h = (self.easy_init)();
            if h.is_null() {
                return Err(-1);
            }
            (self.setopt_ptr)(h, CURLOPT_URL, c_url.as_ptr() as *const c_void);
            (self.setopt_long)(h, CURLOPT_TIMEOUT, timeout_secs);
            (self.setopt_long)(h, CURLOPT_FOLLOWLOCATION, 1);
            (self.setopt_long)(h, CURLOPT_NOSIGNAL, 1);
            if let Some(ref d) = c_doh {
                (self.setopt_ptr)(h, CURLOPT_DOH_URL, d.as_ptr() as *const c_void);
            }
            let cb: WriteCallback = write_vec_cb;
            (self.setopt_ptr)(h, CURLOPT_WRITEFUNCTION, cb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_WRITEDATA, &mut body as *mut Vec<u8> as *const c_void);

            let rc = (self.easy_perform)(h);
            let mut status: c_long = 0;
            if rc == 0 {
                (self.getinfo_long)(h, CURLINFO_RESPONSE_CODE, &mut status);
            }
            (self.easy_cleanup)(h);
            if rc != 0 {
                Err(rc)
            } else {
                Ok((status, body))
            }
        }
    }

    fn get_discard(&self, url: &str, timeout_secs: c_long) -> Result<(c_long, u64), c_int> {
        let c_url = CString::new(url).map_err(|_| -1)?;
        let mut count: u64 = 0;
        unsafe {
            let h = (self.easy_init)();
            if h.is_null() {
                return Err(-1);
            }
            (self.setopt_ptr)(h, CURLOPT_URL, c_url.as_ptr() as *const c_void);
            (self.setopt_long)(h, CURLOPT_TIMEOUT, timeout_secs);
            (self.setopt_long)(h, CURLOPT_FOLLOWLOCATION, 1);
            (self.setopt_long)(h, CURLOPT_NOSIGNAL, 1);
            let cb: WriteCallback = write_count_cb;
            (self.setopt_ptr)(h, CURLOPT_WRITEFUNCTION, cb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_WRITEDATA, &mut count as *mut u64 as *const c_void);

            let rc = (self.easy_perform)(h);
            let mut status: c_long = 0;
            if rc == 0 {
                (self.getinfo_long)(h, CURLINFO_RESPONSE_CODE, &mut status);
            }
            (self.easy_cleanup)(h);
            if rc != 0 {
                Err(rc)
            } else {
                Ok((status, count))
            }
        }
    }

    fn post_filler(&self, url: &str, total_bytes: u64, timeout_secs: c_long) -> Result<(c_long, u64), c_int> {
        let c_url = CString::new(url).map_err(|_| -1)?;
        let mut state = UploadState {
            remaining: total_bytes,
            sent: 0,
        };
        let mut discard: u64 = 0;
        unsafe {
            let h = (self.easy_init)();
            if h.is_null() {
                return Err(-1);
            }
            (self.setopt_ptr)(h, CURLOPT_URL, c_url.as_ptr() as *const c_void);
            (self.setopt_long)(h, CURLOPT_TIMEOUT, timeout_secs);
            (self.setopt_long)(h, CURLOPT_POST, 1);
            (self.setopt_long)(h, CURLOPT_NOSIGNAL, 1);
            (self.setopt_i64)(h, CURLOPT_POSTFIELDSIZE_LARGE, total_bytes as i64);

            let rcb: ReadCallback = read_filler_cb;
            (self.setopt_ptr)(h, CURLOPT_READFUNCTION, rcb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_READDATA, &mut state as *mut UploadState as *const c_void);

            let wcb: WriteCallback = write_count_cb;
            (self.setopt_ptr)(h, CURLOPT_WRITEFUNCTION, wcb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_WRITEDATA, &mut discard as *mut u64 as *const c_void);

            let rc = (self.easy_perform)(h);
            let mut status: c_long = 0;
            if rc == 0 {
                (self.getinfo_long)(h, CURLINFO_RESPONSE_CODE, &mut status);
            }
            (self.easy_cleanup)(h);
            if rc != 0 {
                Err(rc)
            } else {
                Ok((status, state.sent))
            }
        }
    }
}

impl Drop for LibCurl {
    fn drop(&mut self) {
        unsafe {
            dlclose(self.lib);
        }
    }
}

struct UploadState {
    remaining: u64,
    sent: u64,
}

unsafe extern "C" fn write_vec_cb(
    ptr: *const c_char,
    size: usize,
    nmemb: usize,
    userdata: *mut c_void,
) -> usize {
    let n = size.saturating_mul(nmemb);
    if userdata.is_null() || ptr.is_null() {
        return 0;
    }
    let vec = &mut *(userdata as *mut Vec<u8>);
    let slice = std::slice::from_raw_parts(ptr as *const u8, n);
    vec.extend_from_slice(slice);
    n
}

unsafe extern "C" fn write_count_cb(
    _ptr: *const c_char,
    size: usize,
    nmemb: usize,
    userdata: *mut c_void,
) -> usize {
    let n = size.saturating_mul(nmemb);
    if !userdata.is_null() {
        let count = &mut *(userdata as *mut u64);
        *count = count.saturating_add(n as u64);
    }
    n
}

unsafe extern "C" fn read_filler_cb(
    dst: *mut c_char,
    size: usize,
    nmemb: usize,
    userdata: *mut c_void,
) -> usize {
    if userdata.is_null() || dst.is_null() {
        return 0;
    }
    let state = &mut *(userdata as *mut UploadState);
    if state.remaining == 0 {
        return 0;
    }
    let cap = size.saturating_mul(nmemb) as u64;
    let to_write = cap.min(state.remaining) as usize;
    ptr::write_bytes(dst as *mut u8, b'x', to_write);
    state.remaining -= to_write as u64;
    state.sent += to_write as u64;
    to_write
}

fn status_err(code: c_long) -> Option<&'static str> {
    if code == 429 {
        Some("__RATE__")
    } else if (200..300).contains(&code) {
        None
    } else {
        Some("__HTTP__")
    }
}

/// Native speedtest (ping, download, upload) via `libcurl.so.4`.
/// Streams line protocol:
///   PING <ms>
///   DOWN <mbps>
///   UP <mbps>
///   DONE
/// or:
///   ERR <phase> <__FAIL__|__RATE__|__HTTP__|__EMPTY__>
pub fn cmd_net_speedtest(args: &[String]) {
    if args.len() < 3 {
        eprintln!("Usage: net-speedtest <ping_url> <down_url> <up_url>");
        std::process::exit(2);
    }
    let curl = match LibCurl::load() {
        Some(c) => c,
        None => std::process::exit(127),
    };

    let ping_url = &args[0];
    let down_url = &args[1];
    let up_url = &args[2];

    let stdout = io::stdout();
    let mut out = stdout.lock();

    // 1. Ping
    let t0 = Instant::now();
    match curl.get_discard(ping_url, 6) {
        Ok((code, _)) => {
            if let Some(err) = status_err(code) {
                let _ = writeln!(out, "ERR ping {}", err);
                let _ = out.flush();
                return;
            }
            let ms = t0.elapsed().as_millis();
            let _ = writeln!(out, "PING {}", ms);
            let _ = out.flush();
        }
        Err(_) => {
            let _ = writeln!(out, "ERR ping __FAIL__");
            let _ = out.flush();
            return;
        }
    }

    // 2. Download (5s window, max 8 requests)
    let t_dl = Instant::now();
    let mut dl_bytes: u64 = 0;
    for _ in 0..8 {
        if t_dl.elapsed() >= Duration::from_secs(5) {
            break;
        }
        match curl.get_discard(down_url, 6) {
            Ok((code, n)) => {
                if let Some(err) = status_err(code) {
                    let _ = writeln!(out, "ERR download {}", err);
                    let _ = out.flush();
                    return;
                }
                dl_bytes = dl_bytes.saturating_add(n);
            }
            Err(_) => {
                let _ = writeln!(out, "ERR download __FAIL__");
                let _ = out.flush();
                return;
            }
        }
    }
    if dl_bytes < 200_000 {
        let _ = writeln!(out, "ERR download __EMPTY__");
        let _ = out.flush();
        return;
    }
    let dl_ms = t_dl.elapsed().as_millis().max(1000) as f64;
    let dl_mbps = (dl_bytes as f64) * 8.0 / (dl_ms / 1000.0) / 1_000_000.0;
    let _ = writeln!(out, "DOWN {:.1}", dl_mbps);
    let _ = out.flush();

    // 3. Upload (5s window, max 8 requests of 25MB in-memory filler)
    let t_ul = Instant::now();
    let mut ul_bytes: u64 = 0;
    for _ in 0..8 {
        if t_ul.elapsed() >= Duration::from_secs(5) {
            break;
        }
        match curl.post_filler(up_url, 25_000_000, 6) {
            Ok((code, n)) => {
                if let Some(err) = status_err(code) {
                    let _ = writeln!(out, "ERR upload {}", err);
                    let _ = out.flush();
                    return;
                }
                ul_bytes = ul_bytes.saturating_add(n);
            }
            Err(_) => {
                let _ = writeln!(out, "ERR upload __FAIL__");
                let _ = out.flush();
                return;
            }
        }
    }
    if ul_bytes < 200_000 {
        let _ = writeln!(out, "ERR upload __EMPTY__");
        let _ = out.flush();
        return;
    }
    let ul_ms = t_ul.elapsed().as_millis().max(1000) as f64;
    let ul_mbps = (ul_bytes as f64) * 8.0 / (ul_ms / 1000.0) / 1_000_000.0;
    let _ = writeln!(out, "UP {:.1}", ul_mbps);
    let _ = writeln!(out, "DONE");
    let _ = out.flush();
}

/// Minimal URL percent-encoder for Open-Meteo city query parameter.
fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            b' ' => out.push_str("%20"),
            other => {
                use std::fmt::Write as _;
                let _ = write!(out, "%{:02X}", other);
            }
        }
    }
    out
}

/// Native IP geolocation chain (single process, 5 providers including DoH fallback).
/// Emits raw JSON from the first provider that returns valid lat/lon, tagged with
/// `{"provider":"...","body":<raw>}` so QML parses it without spawning 5 curl procs.
pub fn cmd_net_geolocate() {
    let curl = match LibCurl::load() {
        Some(c) => c,
        None => std::process::exit(127),
    };
    let providers: [(&str, &str, Option<&str>); 5] = [
        ("ip-api", "http://ip-api.com/json?fields=lat,lon,city", None),
        ("ipwho.is", "https://ipwho.is/", None),
        ("ipapi.co", "https://ipapi.co/json/", None),
        ("geojs.io", "https://geojs.io/v1/ip/geo.json", None),
        (
            "ipwho.is (DoH)",
            "https://ipwho.is/",
            Some("https://dns.google/dns-query"),
        ),
    ];

    for (id, url, doh) in providers {
        if let Ok((code, bytes)) = curl.get_bytes(url, 8, doh) {
            if (200..300).contains(&code) && !bytes.is_empty() {
                if let Ok(text) = std::str::from_utf8(&bytes) {
                    let trimmed = text.trim();
                    if trimmed.starts_with('{')
                        && (trimmed.contains("\"lat\"") || trimmed.contains("\"latitude\""))
                        && (trimmed.contains("\"lon\"") || trimmed.contains("\"longitude\""))
                    {
                        println!("{{\"provider\":\"{}\",\"body\":{}}}", id, trimmed);
                        return;
                    }
                }
            }
        }
    }
}

/// Native single-shot HTTPS GET helper for Weather geocoding & forecast.
pub fn cmd_net_fetch(args: &[String]) {
    if args.is_empty() {
        std::process::exit(2);
    }
    let curl = match LibCurl::load() {
        Some(c) => c,
        None => std::process::exit(127),
    };
    let url = if args[0] == "--geocode" && args.len() >= 2 {
        format!(
            "https://geocoding-api.open-meteo.com/v1/search?name={}&count=1",
            url_encode(&args[1])
        )
    } else {
        args[0].clone()
    };
    if let Ok((code, bytes)) = curl.get_bytes(&url, 10, None) {
        if (200..300).contains(&code) {
            let stdout = io::stdout();
            let mut out = stdout.lock();
            let _ = out.write_all(&bytes);
            let _ = out.flush();
        }
    }
}
