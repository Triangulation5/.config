use serde::Serialize;
use serde_json::{Deserializer, Value};
use std::{
    collections::{BTreeSet, HashMap},
    io::{self, BufReader, Write},
    process::{Command, Stdio},
};

#[derive(Default, PartialEq, Eq, Serialize)]
struct SourceUsers {
    apps: Vec<String>,
    devices: Vec<String>,
}

#[derive(Default, PartialEq, Eq, Serialize)]
struct PrivacySnapshot {
    #[serde(rename = "audioIn")]
    audio_in: SourceUsers,
    camera: SourceUsers,
    #[serde(rename = "audioOut")]
    audio_out: SourceUsers,
}

#[derive(Clone, Debug)]
struct NodeInfo {
    media_class: String,
    app: String,
    description: String,
}

#[derive(Clone, Copy, Debug)]
struct LinkInfo {
    out_node: u64,
    in_node: u64,
}

fn clean_app(name: &str) -> String {
    let leaf = name.rsplit('/').next().unwrap_or(name);
    let without_on = if let Some(idx) = leaf.to_ascii_lowercase().find(" on ") {
        &leaf[..idx]
    } else {
        leaf
    };
    if without_on.starts_with("alsa_input.") || without_on.starts_with("alsa_output.") {
        return String::new();
    }
    let trimmed = without_on.trim();
    if trimmed.ends_with(')') {
        if let Some(open) = trimmed.rfind('(') {
            return trimmed[..open].trim().to_string();
        }
    }
    trimmed.to_string()
}

fn clean_device(name: &str) -> String {
    let trimmed = name.trim();
    let stripped = if trimmed.ends_with(']') {
        if let Some(open) = trimmed.rfind('[') {
            trimmed[..open].trim()
        } else {
            trimmed
        }
    } else {
        trimmed
    };
    stripped.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn build_snapshot(nodes: &HashMap<u64, NodeInfo>, links: &HashMap<u64, LinkInfo>) -> PrivacySnapshot {
    let mut in_audio_apps = BTreeSet::new();
    let mut in_audio_devs = BTreeSet::new();
    let mut cam_apps = BTreeSet::new();
    let mut cam_devs = BTreeSet::new();
    let mut out_audio_apps = BTreeSet::new();
    let mut out_audio_devs = BTreeSet::new();

    for (&node_id, node) in nodes {
        let (target_apps, target_devs, is_out) = match node.media_class.as_str() {
            "Stream/Input/Audio" => (&mut in_audio_apps, &mut in_audio_devs, false),
            "Stream/Output/Audio" => (&mut out_audio_apps, &mut out_audio_devs, true),
            "Stream/Input/Video" => (&mut cam_apps, &mut cam_devs, false),
            other if other.starts_with("Stream/") && other.contains("Video") && !other.contains("Output") => {
                (&mut cam_apps, &mut cam_devs, false)
            }
            _ => continue,
        };

        let app = clean_app(&node.app);
        if !app.is_empty() {
            target_apps.insert(app);
        }

        for link in links.values() {
            let peer_id = if is_out && link.out_node == node_id {
                Some(link.in_node)
            } else if !is_out && link.in_node == node_id {
                Some(link.out_node)
            } else {
                None
            };
            if let Some(pid) = peer_id {
                if let Some(peer) = nodes.get(&pid) {
                    let dev = clean_device(&peer.description);
                    if !dev.is_empty() {
                        target_devs.insert(dev);
                    }
                }
            }
        }
    }

    PrivacySnapshot {
        audio_in: SourceUsers {
            apps: in_audio_apps.into_iter().collect(),
            devices: in_audio_devs.into_iter().collect(),
        },
        camera: SourceUsers {
            apps: cam_apps.into_iter().collect(),
            devices: cam_devs.into_iter().collect(),
        },
        audio_out: SourceUsers {
            apps: out_audio_apps.into_iter().collect(),
            devices: out_audio_devs.into_iter().collect(),
        },
    }
}

fn apply_batch(
    batch: Vec<Value>,
    nodes: &mut HashMap<u64, NodeInfo>,
    links: &mut HashMap<u64, LinkInfo>,
) {
    for obj in batch {
        let Some(id) = obj.get("id").and_then(Value::as_u64) else {
            continue;
        };
        let info = obj.get("info");
        if info.is_none() || info.is_some_and(Value::is_null) {
            nodes.remove(&id);
            links.remove(&id);
            continue;
        }
        let Some(info) = info else {
            continue;
        };
        let kind = obj.get("type").and_then(Value::as_str).unwrap_or("");
        match kind {
            "PipeWire:Interface:Node" => {
                let props = info.get("props");
                let media_class = props
                    .and_then(|p| p.get("media.class"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let app = props
                    .and_then(|p| {
                        p.get("application.name")
                            .or_else(|| p.get("node.name"))
                            .or_else(|| p.get("node.description"))
                    })
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let description = props
                    .and_then(|p| {
                        p.get("node.description")
                            .or_else(|| p.get("node.nick"))
                            .or_else(|| p.get("node.name"))
                    })
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                nodes.insert(
                    id,
                    NodeInfo {
                        media_class,
                        app,
                        description,
                    },
                );
            }
            "PipeWire:Interface:Link" => {
                let out_node = info.get("output-node-id").and_then(Value::as_u64);
                let in_node = info.get("input-node-id").and_then(Value::as_u64);
                if let (Some(out_node), Some(in_node)) = (out_node, in_node) {
                    links.insert(id, LinkInfo { out_node, in_node });
                }
            }
            _ => {}
        }
    }
}

pub(crate) fn watch() -> Result<(), String> {
    let mut child = Command::new("pw-dump")
        .args(["--monitor", "--no-colors"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("failed to spawn pw-dump: {error}"))?;

    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "pw-dump stdout unavailable".to_string())?;

    let mut nodes: HashMap<u64, NodeInfo> = HashMap::new();
    let mut links: HashMap<u64, LinkInfo> = HashMap::new();
    let mut last_emitted: Option<PrivacySnapshot> = None;
    let mut out = io::stdout().lock();

    let stream = Deserializer::from_reader(BufReader::new(stdout)).into_iter::<Vec<Value>>();
    for item in stream {
        let batch = match item {
            Ok(batch) => batch,
            Err(_) => break,
        };
        apply_batch(batch, &mut nodes, &mut links);
        let snapshot = build_snapshot(&nodes, &links);
        if last_emitted.as_ref() != Some(&snapshot) {
            if serde_json::to_writer(&mut out, &snapshot).is_err()
                || out.write_all(b"\n").is_err()
                || out.flush().is_err()
            {
                let _ = child.kill();
                let _ = child.wait();
                return Ok(());
            }
            last_emitted = Some(snapshot);
        }
    }

    let _ = child.kill();
    let _ = child.wait();
    Err("pw-dump stream ended".to_string())
}
