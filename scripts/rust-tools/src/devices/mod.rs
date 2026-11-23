mod backlight;
mod bluetooth;
mod wifi;

use std::io::{self, Write};

pub(crate) fn run(operation: &str, arg: Option<&str>) -> bool {
    match operation {
        "wifi-state" => match wifi::query_state() {
            Ok(state) => {
                serde_json::to_writer(io::stdout(), &state).is_ok()
                    && io::stdout().write_all(b"\n").is_ok()
            }
            Err(error) => {
                eprintln!("device-ctl wifi-state: {error}");
                false
            }
        },
        "wifi-rescan" => match wifi::request_rescan() {
            Ok(()) => true,
            Err(error) => {
                eprintln!("device-ctl wifi-rescan: {error}");
                false
            }
        },
        "bt-pair" => {
            let Some(mac) = arg.filter(|s| !s.trim().is_empty()) else {
                eprintln!("device-ctl bt-pair: missing MAC address");
                return false;
            };
            match bluetooth::pair_trust_connect(mac) {
                Ok(()) => true,
                Err(error) => {
                    eprintln!("device-ctl bt-pair: {error}");
                    false
                }
            }
        }
        "backlight" => {
            let state = backlight::read_backlight();
            serde_json::to_writer(io::stdout(), &state).is_ok()
                && io::stdout().write_all(b"\n").is_ok()
        }
        other => {
            eprintln!("device-ctl: unknown operation '{other}'");
            false
        }
    }
}
