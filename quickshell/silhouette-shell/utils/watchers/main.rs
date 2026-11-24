mod curl;
mod dbus;
mod emoji;
mod fs_watch;
mod hypr;
mod net;
mod system;
mod thumbs;

use std::env;

pub(crate) fn parse_u64_flag(args: &[String], flag: &str, default: u64) -> u64 {
    let mut i = 0;
    while i + 1 < args.len() {
        if args[i] == flag {
            if let Ok(v) = args[i + 1].parse::<u64>() {
                return v;
            }
        }
        i += 1;
    }
    default
}

pub(crate) fn parse_str_flag<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    let mut i = 0;
    while i + 1 < args.len() {
        if args[i] == flag {
            return Some(args[i + 1].as_str());
        }
        i += 1;
    }
    None
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!(
            "Usage: silhouette_watchers <backlight-watch|hypr-barlayout|hypr-fullscreen|hypr-workspacerules|downloads-probe|stat-watch|file-wait|proc-watch> [args]"
        );
        std::process::exit(2);
    }
    match args[1].as_str() {
        "backlight-watch" => fs_watch::cmd_backlight_watch(),
        "hypr-barlayout" => hypr::cmd_hypr_barlayout(&args[2..]),
        "hypr-fullscreen" => hypr::cmd_hypr_fullscreen(),
        "hypr-workspacerules" => hypr::cmd_hypr_workspacerules(),
        "downloads-probe" => fs_watch::cmd_downloads_probe(),
        "stat-watch" => fs_watch::cmd_stat_watch(&args[2..]),
        "file-wait" => fs_watch::cmd_file_wait(&args[2..]),
        "proc-watch" => fs_watch::cmd_proc_watch(&args[2..]),
        "logind-watch" => dbus::cmd_logind_watch(),
        "net-speedtest" => net::cmd_net_speedtest(&args[2..]),
        "net-geolocate" => net::cmd_net_geolocate(),
        "net-fetch" => net::cmd_net_fetch(&args[2..]),
        "thumbs-walls" => thumbs::cmd_thumbs_walls(&args[2..]),
        "thumbs-cliphist" => thumbs::cmd_thumbs_cliphist(&args[2..]),
        "thumbs-rec" => thumbs::cmd_thumbs_rec(&args[2..]),
        "hotspot-state" => system::cmd_hotspot_state(&args[2..]),
        "hypr-slurp" => hypr::cmd_hypr_slurp(),
        "emoji-match" => emoji::cmd_emoji_match(&args[2..]),
        "net-local-ip" => net::cmd_net_local_ip(),
        "cursor-themes" => system::cmd_cursor_themes(),
        "clip-copy" => system::cmd_clip_copy(&args[2..]),
        "clip-delete" => system::cmd_clip_delete(&args[2..]),
        "write-file" => system::cmd_write_file(&args[2..]),
        other => {
            eprintln!("Unknown subcommand: {}", other);
            std::process::exit(2);
        }
    }
}
