local dwmStyle = require("modules.style").dwmStyle

-- https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- 10 workspaces for dwmStyle, 5 otherwise
local workspaceCount = dwmStyle and 10 or 5

for i = 1, workspaceCount do
    hl.workspace_rule({ workspace = tostring(i), monitor = "", persistent = true })
end

hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1.25,
})

hl.monitor({
    output   = "HDMI-A-2",
    mode     = "1920x1080@60",
    position = "1280x0",
    scale    = 1,
})
