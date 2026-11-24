use crate::curl::LibCurl;
use std::ffi::{c_char, c_int, c_long, c_uint, c_void};
use std::io::{self, Write};
use std::ptr;
use std::sync::OnceLock;
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

static LOCAL_IPV4: OnceLock<Option<String>> = OnceLock::new();

fn query_local_ipv4() -> Option<String> {
    unsafe {
        let mut head: *mut IfAddrs = ptr::null_mut();
        if getifaddrs(&mut head) != 0 || head.is_null() {
            return None;
        }
        let mut found = None;
        let mut cur = head;
        while !cur.is_null() {
            let ifa = &*cur;
            let up = (ifa.ifa_flags & IFF_UP) != 0;
            let loopback = (ifa.ifa_flags & IFF_LOOPBACK) != 0;
            if up && !loopback && !ifa.ifa_addr.is_null() {
                let sa = &*ifa.ifa_addr;
                if sa.sa_family == AF_INET {
                    let a = sa.sa_data[2];
                    let b = sa.sa_data[3];
                    let c = sa.sa_data[4];
                    let d = sa.sa_data[5];
                    if a != 127 && !(a == 169 && b == 254) {
                        found = Some(format!("{}.{}.{}.{}", a, b, c, d));
                        break;
                    }
                }
            }
            cur = ifa.ifa_next;
        }
        freeifaddrs(head);
        found
    }
}

/// Prints the first active global IPv4 address via cached `getifaddrs()`.
pub fn cmd_net_local_ip() {
    if let Some(ip) = LOCAL_IPV4.get_or_init(query_local_ipv4) {
        println!("{}", ip);
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_escapes_spaces_and_symbols() {
        assert_eq!(url_encode("New York"), "New%20York");
        assert_eq!(url_encode("a-b_c.d~1"), "a-b_c.d~1");
        assert_eq!(url_encode("a&b=c"), "a%26b%3Dc");
    }

    #[test]
    fn status_err_maps_http_codes() {
        assert_eq!(status_err(200), None);
        assert_eq!(status_err(204), None);
        assert_eq!(status_err(429), Some("__RATE__"));
        assert_eq!(status_err(503), Some("__HTTP__"));
    }
}
