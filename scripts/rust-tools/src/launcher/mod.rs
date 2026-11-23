mod scorer;

use scorer::{IndexedEntry, Matcher};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    io::{self, BufRead, BufReader, Write},
};

#[derive(Deserialize)]
struct EntryInput {
    #[serde(default)]
    id: String,
    #[serde(default)]
    name: String,
    #[serde(rename = "genericName", default)]
    generic_name: Option<String>,
    #[serde(default)]
    keywords: Vec<String>,
}

#[derive(Deserialize)]
#[serde(tag = "cmd", rename_all = "lowercase")]
enum Request {
    Index {
        entries: Vec<EntryInput>,
    },
    Usage {
        usage: HashMap<String, u32>,
    },
    Query {
        seq: u64,
        #[serde(default)]
        q: String,
    },
}

#[derive(Serialize)]
struct QueryResponse<'a> {
    seq: u64,
    indices: &'a [usize],
}

/// Persistent JSONL fuzzy-ranking daemon for the launcher.
/// Reads index/usage/query lines from stdin and writes ranked index arrays to stdout.
pub(crate) fn run() -> bool {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let reader = BufReader::new(stdin.lock());
    let mut out = stdout.lock();

    let mut matcher = Matcher::new();
    let mut indices: Vec<usize> = Vec::new();

    for line in reader.lines() {
        let Ok(line) = line else {
            break;
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Ok(req) = serde_json::from_str::<Request>(trimmed) else {
            continue;
        };
        match req {
            Request::Index { entries } => {
                let indexed = entries
                    .into_iter()
                    .map(|e| {
                        IndexedEntry::new(
                            e.id,
                            &e.name,
                            e.generic_name.as_deref(),
                            &e.keywords,
                            0,
                        )
                    })
                    .collect();
                matcher.set_entries(indexed);
            }
            Request::Usage { usage } => {
                matcher.set_usage(usage);
            }
            Request::Query { seq, q } => {
                matcher.rank(&q, &mut indices);
                let resp = QueryResponse {
                    seq,
                    indices: &indices,
                };
                if serde_json::to_writer(&mut out, &resp).is_err()
                    || out.write_all(b"\n").is_err()
                    || out.flush().is_err()
                {
                    break;
                }
            }
        }
    }

    true
}
