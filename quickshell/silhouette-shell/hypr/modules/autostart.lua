-- Hyprland autostart module.
--
-- This module is intended to live at ~/.config/hypr/modules/autostart.lua
-- and be loaded from the main Hyprland config with:
--   source = ~/.config/hypr/modules/autostart.lua
--
-- Keep autostart entries safe: if a command is missing or fails to start,
-- it should not take down the session.

local hypridle_bin = "/usr/bin/hypridle"

-- Start hypridle if the binary exists. If it is already running elsewhere,
-- or cannot start for some other reason, this should still be harmless.
if hypridle_bin and pcall(function () assert(io.open(hypridle_bin, "r")) end) then
    exec-once = hypridle_bin
end
