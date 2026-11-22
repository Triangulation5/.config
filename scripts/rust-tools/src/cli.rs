use clap::{Parser, Subcommand, ValueEnum};
use std::{ffi::OsString, path::PathBuf};

#[derive(Parser)]
#[command(name = "silhouette-tools")]
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
    #[command(name = "package-updates")]
    PackageUpdates {
        #[arg(value_enum)]
        operation: PackageUpdateOperation,
    },
    #[command(name = "privacy-watch")]
    PrivacyWatch,
    #[command(name = "polkit-agent")]
    PolkitAgent {
        #[arg(long)]
        config: Option<PathBuf>,
    },
    Watchdog {
        name: String,
        #[arg(long)]
        scripts_dir: Option<PathBuf>,
    },
    Backup {
        #[arg(value_enum)]
        action: BackupAction,
        name: Option<String>,
        #[arg(long)]
        shell: Option<PathBuf>,
        #[arg(long)]
        state: Option<PathBuf>,
        #[arg(long)]
        dir: Option<PathBuf>,
    },
    Wallcolors {
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

#[derive(Clone, Copy, ValueEnum)]
pub(crate) enum PackageUpdateOperation {
    Check,
    Apply,
    #[value(name = "apply-minimal")]
    ApplyMinimal,
}

#[derive(Clone, Copy, ValueEnum)]
pub(crate) enum BackupAction {
    Create,
    List,
    Restore,
    Remove,
}
