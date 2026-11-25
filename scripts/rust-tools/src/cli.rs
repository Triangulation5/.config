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
    #[command(name = "launcher-match")]
    LauncherMatch,
    #[command(name = "device-ctl")]
    DeviceCtl {
        operation: String,
        arg: Option<String>,
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
    #[command(name = "open-surface")]
    OpenSurface {
        surface: String,
        arg: Option<String>,
    },
    #[command(name = "quick-record")]
    QuickRecord,
    #[command(name = "minimize-toggle")]
    MinimizeToggle,
    #[command(name = "special-toggle")]
    SpecialToggle {
        name: Option<String>,
    },
    Gamemode {
        mode: String,
    },
    #[command(name = "wake-display")]
    WakeDisplay,
    #[command(name = "kitty-opacity")]
    KittyOpacity,
    #[command(name = "display-apply")]
    DisplayApply {
        verb: String,
        out: String,
        #[arg(allow_hyphen_values = true)]
        mode: Option<String>,
        #[arg(allow_hyphen_values = true)]
        position: Option<String>,
        #[arg(allow_hyphen_values = true)]
        scale: Option<String>,
    },
    #[command(name = "display-rollback-wait", hide = true)]
    DisplayRollbackWait {
        pending: PathBuf,
        old: PathBuf,
        token: String,
    },
    #[command(name = "lock-wallpaper")]
    LockWallpaper {
        pic: Option<PathBuf>,
    },
    Lock,
    #[command(name = "launch-guard")]
    LaunchGuard {
        #[arg(allow_hyphen_values = true)]
        name: String,
        #[arg(allow_hyphen_values = true)]
        icon: String,
        #[arg(allow_hyphen_values = true)]
        workdir: String,
        #[arg(num_args = 1.., trailing_var_arg = true, allow_hyphen_values = true)]
        argv: Vec<OsString>,
    },
    #[command(name = "note-inbox")]
    NoteInbox {
        #[arg(short = 't', long = "timestamp")]
        timestamp: bool,
    },
    #[command(name = "session-start")]
    SessionStart,
    #[command(name = "awww-daemon")]
    AwwwDaemon {
        #[arg(default_value = "status")]
        action: String,
    },
    #[command(name = "cliphist-watch")]
    CliphistWatch,
    #[command(name = "user-service")]
    UserService {
        cmd: String,
        service: String,
    },
    Inhibit {
        #[arg(num_args = 1.., trailing_var_arg = true, allow_hyphen_values = true)]
        argv: Vec<OsString>,
    },
    Power {
        action: String,
    },
    #[command(name = "migrate-state")]
    MigrateState,
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
