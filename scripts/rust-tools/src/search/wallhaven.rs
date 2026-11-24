use super::providers::safe_filter;
use crate::{
    config::{client, state_dir},
    model::Entry,
};
use fs2::FileExt;
use std::{
    env, fs,
    fs::{File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

fn wh_state() -> PathBuf {
    let base = state_dir().join("silhouette");
    let _ = fs::create_dir_all(&base);
    base
}

pub(super) fn wh_gate(nowait: bool) -> bool {
    let base = wh_state();
    let budget: u32 = env::var("WH_BUDGET")
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|v| *v > 0)
        .unwrap_or(30);
    let lock_path = base.join("wh-window.lock");
    let lock = match OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(lock_path)
    {
        Ok(lock) => lock,
        Err(_) => return false,
    };
    let locked = if nowait {
        lock.try_lock_exclusive().is_ok()
    } else {
        lock.lock_exclusive().is_ok()
    };
    if !locked {
        return false;
    }
    let cooldown = base.join("wh-cooldown.until");
    if let Some(until) = fs::read_to_string(&cooldown)
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
    {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        if now < until {
            if nowait {
                let _ = lock.unlock();
                return false;
            }
            thread::sleep(Duration::from_secs(until - now));
        }
        let _ = fs::remove_file(cooldown);
    }
    let window = base.join("wh-window.ts");
    loop {
        let now_ns = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let mut timestamps = Vec::new();
        if let Ok(file) = File::open(&window) {
            for line in BufReader::new(file).lines().map_while(Result::ok) {
                if let Ok(timestamp) = line.parse::<u128>() {
                    if timestamp + 60_000_000_000 > now_ns {
                        timestamps.push(timestamp);
                    }
                }
            }
        }
        if (timestamps.len() as u32) < budget {
            let mut file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&window)
                .unwrap();
            writeln!(file, "{now_ns}").ok();
            let _ = lock.unlock();
            return true;
        }
        if nowait {
            let _ = lock.unlock();
            return false;
        }
        let oldest = timestamps.first().copied().unwrap_or(now_ns);
        let need_ms = 60_000u128.saturating_sub((now_ns - oldest) / 1_000_000);
        thread::sleep(Duration::from_millis(if need_ms <= 250 {
            300
        } else {
            need_ms as u64
        }));
    }
}

fn wh_backoff(secs: u64) {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let _ = fs::write(
        wh_state().join("wh-cooldown.until"),
        (now + secs).to_string(),
    );
}

pub(crate) fn whsearch(query: &str, page: u32, want: &str) -> serde_json::Value {
    let mut sort = "favorites";
    let mut extra = "";
    match want {
        "latest" => sort = "date_added",
        "top" => sort = "views",
        "random" => sort = "random",
        "favorites" => sort = "favorites",
        "hot" | "" => {}
        _ => {}
    }
    if (want == "hot" || want.is_empty()) && query.is_empty() {
        sort = "toplist";
        extra = "topRange=1M&";
    }
    let mapped = wh_fetch(query, page, sort, extra);
    if mapped.as_array().is_some_and(|v| v.is_empty())
        && query.split_whitespace().count() > 1
        && query
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == ' ' || c == '-')
    {
        return wh_fetch(
            &query.split_whitespace().collect::<Vec<_>>().join("|"),
            page,
            sort,
            extra,
        );
    }
    mapped
}

fn wh_fetch(query: &str, page: u32, sort: &str, extra: &str) -> serde_json::Value {
    if !wh_gate(true) {
        return serde_json::json!({"wallhaven":"blocked"});
    }
    let enc = urlencoding::encode(query);
    let query_param = if query.is_empty() {
        String::new()
    } else {
        format!("q={enc}&")
    };
    let url = format!("https://wallhaven.cc/api/v1/search?{query_param}sorting={sort}&{extra}order=desc&purity=100&page={page}");
    let Ok(response) = client(15).get(url).send() else {
        return serde_json::json!([]);
    };
    if response.status().as_u16() != 200 {
        wh_backoff(if response.status().as_u16() == 429 {
            120
        } else {
            60
        });
        return serde_json::json!({"wallhaven":"blocked"});
    }
    let Ok(value) = response.json::<serde_json::Value>() else {
        return serde_json::json!([]);
    };
    let mut entries = Vec::new();
    if let Some(data) = value.get("data").and_then(|v| v.as_array()) {
        for item in data {
            let image = item.get("path").and_then(|v| v.as_str()).unwrap_or("");
            if image.is_empty() {
                continue;
            }
            entries.push(Entry {
                image: image.to_string(),
                thumb: item
                    .pointer("/thumbs/large")
                    .and_then(|v| v.as_str())
                    .or_else(|| item.pointer("/thumbs/original").and_then(|v| v.as_str()))
                    .unwrap_or("")
                    .to_string(),
                w: item
                    .get("dimension_x")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0) as u32,
                h: item
                    .get("dimension_y")
                    .and_then(|v| v.as_u64())
                    .unwrap_or(0) as u32,
                source: "wallhaven".to_string(),
                ..Default::default()
            });
        }
    }
    serde_json::to_value(safe_filter(entries)).unwrap_or_else(|_| serde_json::json!([]))
}
