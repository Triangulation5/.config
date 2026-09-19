-- https://wiki.hypr.land/Configuring/Basics/Autostart/

-- cliphist-watch.sh starts the `wl-paste --watch cliphist store` listeners that
-- actually populate the clipboard db. The shell's own wl-paste watcher only
-- fires a change signal so the clipboard surface can refresh, so without this
-- the db is never created: `cliphist list` exits 1 and the surface comes up
-- blank. The script is guarded by pgrep, so it is safe on a config reload.
hl.on("hyprland.start", function ()
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd("bash ~/.config/hypr/scripts/cliphist-watch.sh")
  hl.exec_cmd("bash ~/.config/hypr/scripts/launch.sh")
end)
