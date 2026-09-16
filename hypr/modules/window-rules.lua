-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- The settings app is a standalone dialog, not a tile: floating, at the size its
-- own layout is built for, and centred. Without this its toplevel joins the
-- workspace layout like any other window (and it was coming up at whatever the
-- tile gave it, which is not 900x560). Quickshell's app id is the class; the
-- title naming the window keeps the rule off any future Quickshell window.
hl.window_rule({
    name  = "settings-dialog",
    match = {
        class = "org.quickshell",
        title = "Silhouette Settings",
    },

    float  = true,
    size   = { 900, 560 },
    center = true,
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})
