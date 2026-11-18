use crate::{config::client, model::Entry};
use regex::Regex;
use std::collections::HashSet;

fn blocked_terms() -> &'static [&'static str] {
    &[
        "nsfw",
        "nude",
        "nudity",
        "naked",
        "porn",
        "porno",
        "pornography",
        "pornographic",
        "pornstar",
        "xxx",
        "x-rated",
        "xrated",
        "adult",
        "adultonly",
        "explicit",
        "rule34",
        "r34",
        "hentai",
        "booru",
        "danbooru",
        "gelbooru",
        "konachan",
        "yandere",
        "e621",
        "e926",
        "furry",
        "futanari",
        "futa",
        "yaoi",
        "yuri",
        "shota",
        "shotacon",
        "loli",
        "lolicon",
        "doujin",
        "doujinshi",
        "lewd",
        "lewds",
        "fetish",
        "bdsm",
        "bondage",
        "latex",
        "onlyfans",
        "only-fans",
        "fansly",
        "camgirl",
        "stripper",
        "strip",
        "stripclub",
        "lingerie",
        "underwear",
        "panties",
        "bra",
        "thong",
        "stockings",
        "bikini",
        "swimsuit",
        "swimwear",
        "nipple",
        "nipples",
        "breast",
        "breasts",
        "boob",
        "boobs",
        "cleavage",
        "genitals",
        "genital",
        "vagina",
        "penis",
        "dick",
        "cock",
        "pussy",
        "ass",
        "butt",
        "cum",
        "semen",
        "anal",
        "blowjob",
        "handjob",
        "orgasm",
        "masturbation",
        "masturbate",
        "pornhub",
        "xvideos",
        "xnxx",
        "redtube",
        "youporn",
        "tube8",
        "spankbang",
        "xhamster",
        "brazzers",
        "nsfwart",
        "adultart",
        "rule34art",
        "lewdart",
        "hentaiart",
        "animeporn",
        "animehentai",
        "sexy",
        "sex",
        "sexual",
        "sexually",
    ]
}

pub(super) fn is_blocked(text: &str) -> bool {
    let low = text.to_ascii_lowercase();
    let flat: String = low
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '+')
        .collect();
    let tokens: HashSet<String> = low
        .split(|c: char| !c.is_ascii_alphanumeric() && c != '+')
        .filter(|v| !v.is_empty())
        .map(str::to_owned)
        .collect();
    blocked_terms().iter().any(|term| {
        let term = term.to_ascii_lowercase();
        if term.chars().any(|c| !c.is_ascii_alphanumeric() && c != '+') {
            let word: String = term
                .chars()
                .filter(|c| c.is_ascii_alphanumeric() || *c == '+')
                .collect();
            flat.contains(&word)
        } else {
            tokens.contains(&term)
        }
    })
}

pub(super) fn safe_filter(entries: Vec<Entry>) -> Vec<Entry> {
    entries
        .into_iter()
        .filter(|entry| {
            !is_blocked(&format!(
                "{} {} {} {} {}",
                entry.file, entry.image, entry.thumb, entry.preview, entry.source
            ))
        })
        .collect()
}

pub(crate) fn search_github(query: &str) -> Vec<Entry> {
    let url = "https://api.github.com/repos/Triangulation5/wallpapers/git/trees/main?recursive=1";
    let Ok(response) = client(20)
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .send()
    else {
        return Vec::new();
    };
    let Ok(value) = response.json::<serde_json::Value>() else {
        return Vec::new();
    };
    let words: Vec<String> = query
        .to_ascii_lowercase()
        .split_whitespace()
        .map(str::to_owned)
        .collect();
    let mut entries = Vec::new();
    let Some(tree) = value.get("tree").and_then(|v| v.as_array()) else {
        return entries;
    };
    for item in tree {
        let Some(path) = item.get("path").and_then(|v| v.as_str()) else {
            continue;
        };
        let low = path.to_ascii_lowercase();
        if !matches!(
            low.rsplit('.').next(),
            Some("png" | "jpg" | "jpeg" | "webp" | "gif" | "mp4" | "webm")
        ) {
            continue;
        }
        let hits = words.iter().filter(|word| low.contains(*word)).count();
        if !words.is_empty() && hits != words.len() {
            continue;
        }
        let raw = format!(
            "https://raw.githubusercontent.com/Triangulation5/wallpapers/main/{}",
            urlencoding::encode(path)
        );
        entries.push(Entry {
            image: raw.clone(),
            thumb: raw,
            file: path.to_string(),
            source: "github".to_string(),
            ..Default::default()
        });
    }
    if entries.is_empty() && words.len() > 1 {
        entries.clear();
        for item in tree {
            let Some(path) = item.get("path").and_then(|v| v.as_str()) else {
                continue;
            };
            let low = path.to_ascii_lowercase();
            if words.iter().any(|word| low.contains(word)) {
                let raw = format!(
                    "https://raw.githubusercontent.com/Triangulation5/wallpapers/main/{}",
                    urlencoding::encode(path)
                );
                entries.push(Entry {
                    image: raw.clone(),
                    thumb: raw,
                    file: path.to_string(),
                    source: "github".to_string(),
                    ..Default::default()
                });
            }
        }
    }
    entries.sort_by(|a, b| {
        a.file.len().cmp(&b.file.len()).then_with(|| {
            a.file
                .to_ascii_lowercase()
                .cmp(&b.file.to_ascii_lowercase())
        })
    });
    entries
}

fn html_decode(value: &str) -> String {
    ["&quot;", "&amp;", "&lt;", "&gt;", "&#39;"]
        .iter()
        .fold(value.to_string(), |out, entity| {
            let replacement = match *entity {
                "&quot;" => "\"",
                "&amp;" => "&",
                "&lt;" => "<",
                "&gt;" => ">",
                _ => "'",
            };
            out.replace(entity, replacement)
        })
}

fn search_bing(query: &str, kind: &str) -> Vec<Entry> {
    let url = format!("https://www.bing.com/images/async?q={}&first=1&count=35&mmasync=1&adlt=strict&safeSearch=strict", urlencoding::encode(query));
    let Ok(response) = client(15)
        .get(url)
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
    else {
        return Vec::new();
    };
    let Ok(page) = response.text() else {
        return Vec::new();
    };
    let re = Regex::new(r#"m="([^"]+)""#).unwrap();
    let gif = Regex::new(r"(?i)\.gif(\?|$)").unwrap();
    let mut seen = HashSet::new();
    let mut entries = Vec::new();
    for capture in re.captures_iter(&page) {
        let blob = html_decode(capture.get(1).unwrap().as_str());
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&blob) else {
            continue;
        };
        let image = value.get("murl").and_then(|v| v.as_str()).unwrap_or("");
        if !image.starts_with("http") || !seen.insert(image.to_string()) {
            continue;
        }
        if kind == "still" && gif.is_match(image) {
            continue;
        }
        let thumb = value.get("turl").and_then(|v| v.as_str()).unwrap_or(image);
        entries.push(Entry {
            image: image.to_string(),
            thumb: thumb.to_string(),
            source: "bing".to_string(),
            ..Default::default()
        });
    }
    entries
}

fn search_ddg(query: &str, kind: &str) -> Vec<Entry> {
    let enc = urlencoding::encode(query);
    let Ok(page) = client(10)
        .get(format!(
            "https://duckduckgo.com/?q={enc}&iax=images&ia=images"
        ))
        .send()
        .and_then(|r| r.text())
    else {
        return Vec::new();
    };
    let re = Regex::new(r#"vqd=(?:\\?"?)?([0-9-]+)"#).unwrap();
    let Some(vqd) = re
        .captures(&page)
        .and_then(|c| c.get(1))
        .map(|v| v.as_str())
    else {
        return Vec::new();
    };
    let f = if kind == "still" {
        "type:photo"
    } else {
        ",,,,"
    };
    let url = format!("https://duckduckgo.com/i.js?l=us-en&o=json&q={enc}&vqd={vqd}&f={f}&p=2");
    let Ok(response) = client(10)
        .get(url)
        .header("Referer", "https://duckduckgo.com/")
        .send()
    else {
        return Vec::new();
    };
    let Ok(value) = response.json::<serde_json::Value>() else {
        return Vec::new();
    };
    let mut entries = Vec::new();
    if let Some(results) = value.get("results").and_then(|v| v.as_array()) {
        for item in results {
            let image = item.get("image").and_then(|v| v.as_str()).unwrap_or("");
            if image.is_empty() {
                continue;
            }
            if kind == "still" && Regex::new(r"(?i)\.gif(\?|$)").unwrap().is_match(image) {
                continue;
            }
            entries.push(Entry {
                image: image.to_string(),
                thumb: item
                    .get("thumbnail")
                    .and_then(|v| v.as_str())
                    .unwrap_or(image)
                    .to_string(),
                source: "duckduckgo".to_string(),
                w: item.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
                h: item.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
                ..Default::default()
            });
        }
    }
    entries
}

fn search_moewalls(query: &str) -> Vec<Entry> {
    let http = client(12);
    let Ok(page) = http
        .get(format!(
            "https://moewalls.com/?s={}",
            urlencoding::encode(query)
        ))
        .header("Referer", "https://moewalls.com/")
        .send()
        .and_then(|r| r.text())
    else {
        return Vec::new();
    };
    let post_re =
        Regex::new(r#"href="(https://moewalls\.com/[a-z0-9-]+/[a-z0-9-]+-live-wallpaper/)""#)
            .unwrap();
    let mut posts = Vec::new();
    let mut seen = HashSet::new();
    for capture in post_re.captures_iter(&page) {
        let post = capture.get(1).unwrap().as_str();
        if seen.insert(post.to_string()) {
            posts.push(post.to_string());
        }
        if posts.len() == 24 {
            break;
        }
    }
    let mut entries = Vec::new();
    for post in posts {
        let Ok(html) = http
            .get(&post)
            .header("Referer", "https://moewalls.com/")
            .send()
            .and_then(|r| r.text())
        else {
            continue;
        };
        let preview_re =
            Regex::new(r#"<source src="(/wp-content/uploads/preview/[^"]+)""#).unwrap();
        let token_re = Regex::new(r#"id="moe-download"[^>]*data-url="([^"]+)""#).unwrap();
        let thumb_re = Regex::new(r#"poster="([^"]+)""#).unwrap();
        let preview = preview_re
            .captures(&html)
            .and_then(|c| c.get(1))
            .map(|v| format!("https://moewalls.com{}", v.as_str()))
            .unwrap_or_default();
        let Some(token) = token_re.captures(&html).and_then(|c| c.get(1)) else {
            continue;
        };
        let thumb = thumb_re
            .captures(&html)
            .and_then(|c| c.get(1))
            .map(|v| v.as_str())
            .unwrap_or("");
        entries.push(Entry {
            image: format!(
                "https://go.moewalls.com/download.php?video={}",
                token.as_str()
            ),
            thumb: if thumb.is_empty() {
                preview.clone()
            } else {
                format!("https://moewalls.com/{thumb}")
            },
            preview,
            source: "moewalls".to_string(),
            ..Default::default()
        });
    }
    entries
}

pub(crate) fn search(query: &str, kind: &str) -> Vec<Entry> {
    let (query, kind) = if let Some(rest) = query.strip_prefix("gh:") {
        (rest.to_string(), "github".to_string())
    } else {
        (query.to_string(), kind.to_string())
    };
    if is_blocked(&query) {
        return Vec::new();
    }
    if query.is_empty() && kind != "github" && kind != "repo" {
        return Vec::new();
    }
    let repo = safe_filter(search_github(&query));
    if matches!(kind.as_str(), "repo" | "github") {
        return repo;
    }
    if kind == "motion" {
        let mut entries = repo;
        entries.extend(safe_filter(search_moewalls(&query)));
        return entries;
    }
    if !repo.is_empty() {
        return repo;
    }
    let mut entries = safe_filter(search_bing(&query, &kind));
    if entries.is_empty() {
        entries = safe_filter(search_ddg(&query, &kind));
    }
    entries
}
