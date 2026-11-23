mod apps;
mod backup;
mod cli;
mod config;
mod devices;
mod launcher;
mod model;
mod polkit;
mod privacy;
mod search;
mod thumbnails;
mod updates;
mod wallcolors;
mod wallpaper;
mod watchdog;

use clap::Parser;
use cli::{BackupAction, Cli, Commands, PackageUpdateOperation};
use std::{
    io::{self, Write},
    path::Path,
};

fn main() {
    let cli = Cli::parse();
    let ok = match cli.command {
        Commands::WallpaperThumbs => thumbnails::wallpaper_thumbnails().map_or_else(
            |error| {
                eprintln!("wallpaper-thumbs: {error}");
                false
            },
            |_| true,
        ),
        Commands::CliphistThumbs => thumbnails::cliphist_thumbnails().map_or_else(
            |error| {
                eprintln!("cliphist-thumbs: {error}");
                false
            },
            |_| true,
        ),
        Commands::RecThumbs { recording_dir } => thumbnails::recording_thumbnails(
            recording_dir
                .as_deref()
                .filter(|value| !value.is_empty())
                .map(Path::new),
        )
        .map_or_else(
            |error| {
                eprintln!("rec-thumbs: {error}");
                false
            },
            |_| true,
        ),
        Commands::AppInstall { operation, args } => apps::app_install(&operation, &args)
            .map_or_else(
                |error| {
                    eprintln!("app-install: {error}");
                    false
                },
                |_| true,
            ),
        Commands::AppImageInstall { operation, args } => apps::appimage_install(&operation, &args)
            .map_or_else(
                |error| {
                    eprintln!("appimage-install: {error}");
                    false
                },
                |_| true,
            ),
        Commands::PackageUpdates { operation } => {
            let operation = match operation {
                PackageUpdateOperation::Check => "check",
                PackageUpdateOperation::Apply => "apply",
                PackageUpdateOperation::ApplyMinimal => "apply-minimal",
            };
            serde_json::to_writer(io::stdout(), &updates::run(operation)).is_ok()
                && io::stdout().write_all(b"\n").is_ok()
        }
        Commands::PrivacyWatch => privacy::watch().map_or_else(
            |error| {
                eprintln!("privacy-watch: {error}");
                false
            },
            |_| true,
        ),
        Commands::PolkitAgent { config } => polkit::run(config.as_deref()),
        Commands::Watchdog { name, scripts_dir } => watchdog::run(&name, scripts_dir.as_deref()),
        Commands::LauncherMatch => launcher::run(),
        Commands::DeviceCtl { operation, arg } => devices::run(&operation, arg.as_deref()),
        Commands::Backup {
            action,
            name,
            shell,
            state,
            dir,
        } => {
            let action = match action {
                BackupAction::Create => "create",
                BackupAction::List => "list",
                BackupAction::Restore => "restore",
                BackupAction::Remove => "remove",
            };
            backup::run(
                action,
                name.as_deref(),
                shell.as_deref(),
                state.as_deref(),
                dir.as_deref(),
            )
        }
        Commands::Wallcolors { args } => wallcolors::run(&args),
        Commands::Search { query, kind } => {
            let entries = search::search(&query.unwrap_or_default(), &kind);
            let _ = serde_json::to_writer(io::stdout(), &entries);
            let _ = io::stdout().write_all(b"\n");
            true
        }
        Commands::Whsearch { query, page, want } => {
            let value = search::whsearch(&query.unwrap_or_default(), page, &want);
            let _ = serde_json::to_writer(io::stdout(), &value);
            let _ = io::stdout().write_all(b"\n");
            true
        }
        Commands::Thumbget { url } => search::thumbget(&url).is_some_and(|path| {
            let _ = writeln!(io::stdout(), "{}", path.display());
            true
        }),
        Commands::Download { url } => search::download(&url).is_some_and(|path| {
            let _ = writeln!(io::stdout(), "{}", path.display());
            true
        }),
        Commands::Resolve => wallpaper::resolve(),
        Commands::Init => wallpaper::init(),
        Commands::Set { path } => wallpaper::apply_wallpaper(Path::new(&path)),
    };
    if !ok {
        std::process::exit(1);
    }
}
