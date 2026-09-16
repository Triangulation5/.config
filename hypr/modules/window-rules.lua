-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- The settings app is a dialog, not a tile: floating, at the size its own layout
-- is built for, and centred. Without this its toplevel joins the workspace layout
-- like any other window (and it was coming up at whatever the tile gave it, which
-- is not 900x560). Quickshell's app id is the class; the title naming the window
-- keeps the rule off any future Quickshell window.
--
-- The `.*` widens the title to the shell-hosted app and the standalone copy, which
-- appends "(standalone)" so the two can tell each other's window apart. Hyprland
-- anchors rule regexes, so a plain "Silhouette Settings" would miss the suffixed
-- title - measured: the standalone's window came up floating=false size=[560, 672]
-- until this wildcard was added.
--
-- Deliberately not pinned. Pinning draws the dialog on every workspace, which is
-- a dialog that will not go away: it stacks over whatever you switch to. The
-- dialog instead stays on the workspace it was opened on, like any window, and
-- the app moves it to you when you ask for it - see the placement code in
-- quickshell/silhouette-shell/modules/settingsapp/SettingsApp.qml.
hl.window_rule({
    name  = "settings-dialog",
    match = {
        class = "org.quickshell",
        title = "Silhouette Settings.*",
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
