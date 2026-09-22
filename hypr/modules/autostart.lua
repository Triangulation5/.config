-- https://wiki.hypr.land/Configuring/Basics/Autostart/

-- cliphist-watch.sh starts the `wl-paste --watch cliphist store` listeners that
-- actually populate the clipboard db. The shell's own wl-paste watcher only
-- fires a change signal so the clipboard surface can refresh, so without this
-- the db is never created: `cliphist list` exits 1 and the surface comes up
-- blank. The script is guarded by pgrep, so it is safe on a config reload.
hl.on("hyprland.start", function ()
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd("bash ~/.config/hypr/scripts/cliphist-watch.sh")
  -- Started through watchdog.sh, not launch.sh directly: the watchdog is the
  -- launcher and the supervisor in one (it brings a shell up through launch.sh,
  -- then respawns it whenever IPC stops answering), so a shell that dies —
  -- including one that crashes while the session is locked, where its death takes
  -- the in-process lock with it — is back within a few seconds instead of staying
  -- gone until the session is restarted. It takes the config name, and the flock
  -- inside it makes a second call harmless on a config reload.
  --
  -- systemd can hold the same job instead (silhouette-shell.service, versioned in
  -- the shell tree and symlinked into ~/.config/systemd/user); pick one, never
  -- both, or the two supervisors race and leave duplicate shells fighting over the
  -- layer surface.
  hl.exec_cmd("bash ~/.config/hypr/scripts/watchdog.sh silhouette-shell")
end)
