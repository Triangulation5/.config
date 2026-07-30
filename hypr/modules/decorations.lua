-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,

        border_size = 1,

        col = {
            active_border   = { colors = { "rgba(205, 205, 205, 0.15)" } }, -- 0.35
            inactive_border = "rgba(205, 205, 205, 0.08)", -- 0.12
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,
    },

    decoration = {
        rounding       = 5, -- 2, 5, 8, 15
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        shadow = {
            enabled      = true, -- false for minimalism
            range        = 20,
            render_power = 3,
            color        = 0xee121212,
        },

        blur = {
            enabled   = true, -- false for minimalism
            size      = 6, -- 3 default, 8 for decent amount, 20
            passes    = 2, -- 1 default, 2 for decent amount, 3 for frosted glass
            vibrancy  = 0.17, -- 0.1696,
            new_optimizations = true,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- Pill style animations
hl.curve("pillMorph",      { type = "bezier", points = { { 0.16, 1.00 },    { 0.30, 1.00 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })

hl.animation({ leaf = "global",     enabled = true, speed = 4.2,   bezier = "pillMorph" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4.2,   bezier = "pillMorph" })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.2,   bezier = "pillMorph", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4.2, bezier = "pillMorph", style = "popin 92%" })
hl.animation({ leaf = "border",     enabled = true, speed = 4.2,   bezier = "quick" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4.2, bezier = "almostLinear" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 4.2, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 4.2, bezier = "almostLinear" })
hl.animation({ leaf = "layers",        enabled = true, speed = 4.2, bezier = "pillMorph", style = "popin 90%" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 4.2, bezier = "pillMorph" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 4.2, bezier = "pillMorph" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.2, bezier = "pillMorph", style = "slide" })
