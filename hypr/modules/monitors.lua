-- https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

hl.workspace_rule({ workspace = "1", monitor = "", persistent = true})
hl.workspace_rule({ workspace = "2", monitor = "", persistent = true})
hl.workspace_rule({ workspace = "3", monitor = "", persistent = true})
hl.workspace_rule({ workspace = "4", monitor = "", persistent = true})
hl.workspace_rule({ workspace = "5", monitor = "", persistent = true})

hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1.5,
})
