# Silhouette Watchers

Pure std-only Rust daemon/helper binary (`silhouette_watchers`) eliminating continuous shell, `hyprctl`, `stat`, `find`, and `pgrep` fork-exec churn across Tier 1 shell services.

## Subcommands

* `backlight-watch`: Event-driven `/sys/class/backlight` monitor via Linux `NETLINK_KOBJECT_UEVENT` (`SUBSYSTEM=backlight`), emitting brightness percentages (`0..100`) on change. Used by `services/Backlight.qml`.
* `hypr-barlayout [--interval <ms>]`: Connects directly to Hyprland's `.socket2.sock` and `.socket.sock`, emitting single-line JSON `{workspaces, layout}` on layout-relevant events and fallback ticks. Used by `services/BarLayout.qml`.
* `hypr-fullscreen`: Connects to Hyprland's UNIX sockets for fallback fullscreen tracking, emitting `{monitors, workspaces}` on state-changing events. Used by `services/Fullscreen.qml`.
* `hypr-workspacerules`: Connects to Hyprland's UNIX sockets, emitting `{rules, workspaces}` when workspace rules or live workspaces change. Used by `services/Workspacerules.qml`.
* `downloads-probe`: Scans Firefox profile directories for the newest `downloads.json`. Used by `services/Downloads.qml`.
* `stat-watch <path> [--interval <ms>]`: Persistent `stat()` loop emitting file size in bytes. Used by `services/Downloads.qml`.
* `file-wait <path> [--interval <ms>]`: Uses Linux `inotify` to print `yes` and exit the instant `<path>` appears. Used by `services/RecEngine.qml`.
* `proc-watch --mode <rec|claude> [--interval <ms>]`: Persistent `/proc/<pid>/cmdline` scanner emitting `COUNT <n>`. Used by `services/RecEngine.qml` and `modules/desktopwidgets/widgets/catalog.qml`.
* `logind-watch`: Native `libdbus-1.so.3` monitor for `org.freedesktop.login1` (`Lock`, `PrepareForSleep`), emitting `LOCK`, `SUSPEND`, `RESUME`. Used by `services/SuspendWatch.qml`.
* `thumbs-walls <wp_dir> <thumb_dir> <state_file>`: Parallel wallpaper thumbnailer, stale-cache pruner, directory indexer, and state reader emitting JSON. Used by `services/Walls.qml`.
* `thumbs-cliphist <thumb_dir>`: Parallel cliphist image thumbnailer and list parser emitting JSON. Used by `services/Cliphist.qml`.
* `thumbs-rec <out_dir> <thumb_dir> <max> <cleared_before>`: Parallel recording cover-frame thumbnailer and recent list indexer emitting JSON. Used by `services/RecEngine.qml`.
* `net-speedtest <ping_url> <down_url> <up_url>`: Native `libcurl.so.4` ping/download/upload test with in-memory filler buffer and monotonic timing. Used by `modules/pill/surfaces/SysmonSurface.qml`.
* `net-geolocate` / `net-fetch`: Native `libcurl.so.4` geolocation chain (including DoH fallback) and HTTPS fetch. Used by `services/Weather.qml`.
* `hotspot-state <con>`: Consolidated NetworkManager hotspot state + credential reader emitting JSON. Used by `modules/controlcenter/HotspotControl.qml`.
* `hypr-slurp`: Queries Hyprland's UNIX socket for `j/clients` and pipes window rectangles directly to `slurp`, eliminating `sh`/`hyprctl`/`jq`. Used by `services/RecEngine.qml`.
* `emoji-match <emojis.js>`: Persistent stdin/stdout ranked emoji matcher for `modules/launcher/Launcher.qml`.
* `net-local-ip`: Queries `getifaddrs()` directly for the first active global IPv4 address. Used by `modules/controlcenter/Link.qml`.
* `cursor-themes`: Enumerates installed X cursor themes across standard icon directories. Used by `modules/settings/input/Input.qml`.
* `clip-copy <id>` / `clip-delete <id>`: Shell-free `cliphist` copy/delete helpers. Used by `services/Cliphist.qml`.
* `write-file <path> <content>`: Atomic state-file writer. Used by `services/Devices.qml`.

## Building

```bash
./utils/watchers/build.sh
```
