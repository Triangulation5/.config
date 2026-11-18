use clap::{Parser, Subcommand};
use std::ffi::OsString;

#[derive(Parser)]
#[command(name = "wallpaper-rs")]
pub(crate) struct Cli {
    #[command(subcommand)]
    pub(crate) command: Commands,
}

#[derive(Subcommand)]
pub(crate) enum Commands {
    #[command(name = "wallpaper-thumbs")]
    WallpaperThumbs,
    #[command(name = "cliphist-thumbs")]
    CliphistThumbs,
    #[command(name = "rec-thumbs")]
    RecThumbs {
        recording_dir: Option<String>,
    },
    #[command(name = "app-install")]
    AppInstall {
        operation: String,
        #[arg(num_args = 0.., trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<OsString>,
    },
    #[command(name = "appimage-install")]
    AppImageInstall {
        operation: String,
        #[arg(num_args = 0.., trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<OsString>,
    },
    Search {
        query: Option<String>,
        #[arg(default_value = "all")]
        kind: String,
    },
    Whsearch {
        query: Option<String>,
        #[arg(default_value = "1")]
        page: u32,
        #[arg(default_value = "")]
        want: String,
    },
    Thumbget {
        url: String,
    },
    Download {
        url: String,
    },
    Resolve,
    Init,
    Set {
        path: String,
    },
}
