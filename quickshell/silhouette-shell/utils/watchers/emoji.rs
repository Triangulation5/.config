use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::path::Path;

/// Persistent emoji index & matcher for `modules/launcher/Launcher.qml`.
/// Usage: emoji-match <path/to/emojis.js>
/// Protocol:
///   stdin:  <seq>\t<query>\n
///   stdout: {"seq":<seq>,"indices":[...]}\n
pub fn cmd_emoji_match(args: &[String]) {
    let path = match args.first() {
        Some(p) => Path::new(p),
        None => std::process::exit(2),
    };
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => std::process::exit(1),
    };

    let mut names: Vec<String> = Vec::with_capacity(1400);
    for line in content.lines() {
        if let Some(idx) = line.find("n: \"") {
            let rest = &line[idx + 4..];
            if let Some(end) = rest.find('"') {
                names.push(rest[..end].to_ascii_lowercase());
            }
        }
    }

    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let mut line = String::new();
    let mut reader = BufReader::new(stdin.lock());

    // Reusable ranking buffers avoid 3 Vec allocations per keystroke.
    let mut prefix: Vec<usize> = Vec::with_capacity(names.len());
    let mut word: Vec<usize> = Vec::with_capacity(128);
    let mut sub: Vec<usize> = Vec::with_capacity(128);

    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) => {
                let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
                let Some((seq_s, q_raw)) = trimmed.split_once('\t') else {
                    continue;
                };
                let seq: u64 = seq_s.parse().unwrap_or(0);
                let q = q_raw.trim().to_ascii_lowercase();

                prefix.clear();
                word.clear();
                sub.clear();

                if q.is_empty() {
                    prefix.extend(0..names.len());
                } else {
                    for (i, name) in names.iter().enumerate() {
                        if name.starts_with(&q) {
                            prefix.push(i);
                        } else if let Some(pos) = name.find(&q) {
                            let prev = name.as_bytes()[pos - 1];
                            if prev == b' ' || prev == b'-' || prev == b'(' {
                                word.push(i);
                            } else {
                                sub.push(i);
                            }
                        }
                    }
                }

                let _ = write!(out, "{{\"seq\":{},\"indices\":[", seq);
                let mut first = true;
                for &idx in prefix.iter().chain(word.iter()).chain(sub.iter()) {
                    if !first {
                        let _ = write!(out, ",");
                    }
                    first = false;
                    let _ = write!(out, "{}", idx);
                }
                if writeln!(out, "]}}").is_err() || out.flush().is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}
