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
  -- the in-process lock with it — is back within about a second, and within a
  -- quarter of one while the session is locked, where a dead shell leaves the
  -- session open and the watchdog tightens its tick to match. It takes the config
  -- name, and the flock inside it makes a second call harmless on a config reload.
  --
  -- It is the session's only supervisor: the systemd unit that could have held the
  -- same job instead is gone from the shell tree and from ~/.config/systemd/user,
  -- which is deliberate. Running one beside this is the same duplicate-shell hazard
  -- launch.sh and the watchdog already guard against between launches — a second
  -- instance of the same config stacks another layer surface on the monitor and
  -- fights the first one for keyboard focus.
  hl.exec_cmd("bash ~/.config/hypr/scripts/watchdog.sh silhouette-shell")
end)
