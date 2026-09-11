-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function ()
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd("bash ~/.config/hypr/scripts/reload.sh")
  hl.exec_cmd("hypridl && disown")
end)
