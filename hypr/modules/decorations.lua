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
        rounding       = 0, -- 2, 5, 8, 15
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        shadow = {
            enabled      = false, -- false for minimalism
            range        = 20,
            render_power = 3,
            color        = 0xee121212,
        },

        blur = {
            enabled   = false, -- false for minimalism
            size      = 6, -- 3 default, 8 for decent amount, 20
            passes    = 2, -- 1 default, 2 for decent amount, 3 for frosted glass
            vibrancy  = 0.1696,
            new_optimizations = true,
        },
    },

    animations = {
        enabled = false,
    },
})

-- -- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
-- hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
-- hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
-- hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
-- hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
-- hl.curve("easeInOutQuart", { type = "bezier", points = { {0.76, 0},    {0.24, 1}    } })
--
-- -- Default springs
-- hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })
-- hl.curve("instant",        { type = "spring", mass = 0.8, stiffness = 100, dampening = 15 })
-- hl.curve("quicker",        { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })
-- hl.curve("tight",          { type = "spring", mass = 0.8, stiffness = 220, dampening = 30 })
--
-- hl.animation({ leaf = "global",        enabled = true,  speed = 1,    bezier = "default" })
-- hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeInOutQuart" })
-- hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "instant",        style = "popin 99%" })
-- hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 1.1,  spring = "instant",         style = "popin 87%" })
-- hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 2.49, bezier = "easeInOutQuart", style = "popin 87%" })
-- hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
-- hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
-- hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
-- hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeInOutQuart" })
-- hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeInOutQuart", style = "fade" })
-- hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
-- hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
-- hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
-- hl.animation({ leaf = "workspaces",    enabled = true,  speed = 3.94, bezier = "easeInOutQuart", style = "slide" })
-- hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 3.21, bezier = "easeInOutQuart", style = "slide" })
-- hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 3.94, bezier = "easeInOutQuart", style = "slide" })
-- hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Minimal animations for when doing actual work
-- hl.animation({ leaf = "global",        enabled = true, speed = 1,   bezier = "quicker" })
-- hl.animation({ leaf = "windows",       enabled = false, speed = 0.5, spring = "tight" })
-- hl.animation({ leaf = "windowsIn",     enabled = false, speed = 0.3, bezier = "quicker", style = "popin 100%" })
-- hl.animation({ leaf = "windowsOut",    enabled = false, speed = 0.3, bezier = "quicker", style = "popin 96%" })
-- hl.animation({ leaf = "fadeIn",        enabled = true, speed = 0.2, bezier = "linear" })
-- hl.animation({ leaf = "fadeOut",       enabled = true, speed = 0.2, bezier = "linear" })
-- hl.animation({ leaf = "fade",          enabled = true, speed = 0.2, bezier = "linear" })
-- hl.animation({ leaf = "layers",        enabled = true, speed = 4.2, bezier = "quicker" })
-- hl.animation({ leaf = "layersIn",      enabled = true, speed = 2.3, bezier = "quicker", style = "fade" })
-- hl.animation({ leaf = "layersOut",     enabled = true, speed = 2.3, bezier = "quicker", style = "fade" })
-- hl.animation({ leaf = "workspaces",    enabled = true, speed = 0.4, bezier = "quicker", style = "fade" })
-- hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 0.3, bezier = "quicker", style = "fade" })
-- hl.animation({ leaf = "workspacesOut", enabled = true, speed = 0.3, bezier = "quicker", style = "fade" })
-- hl.animation({ leaf = "border",        enabled = true, speed = 1,   bezier = "quicker" })
-- hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 2,   bezier = "quicker" })

-- -- macOS-style curves
-- hl.curve("easeOutQuint",   { type = "bezier", points = { {0.22, 1},    {0.36, 1}    } })
-- hl.curve("easeInOutCubic", { type = "bezier", points = { {0.645, 0.045}, {0.355, 1} } })
-- hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
-- hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
-- hl.curve("quick",          { type = "bezier", points = { {0.25, 0},    {0.1, 1}     } })
-- hl.curve("easeInOutQuart", { type = "bezier", points = { {0.76, 0},    {0.24, 1}    } })
-- hl.curve("macSmooth",      { type = "bezier", points = { {0.16, 1},    {0.3, 1}     } })
--
-- -- macOS-style springs
-- hl.curve("easy",           { type = "spring", mass = 1,   stiffness = 80,  dampening = 18 })
-- hl.curve("instant",        { type = "spring", mass = 0.9, stiffness = 120, dampening = 20 })
-- hl.curve("quicker",        { type = "bezier", points = { {0.25, 0}, {0.1, 1} } })
-- hl.curve("tight",          { type = "spring", mass = 0.85, stiffness = 180, dampening = 28 })
--
-- hl.animation({ leaf = "global",        enabled = true, speed = 1,    bezier = "macSmooth" })
-- hl.animation({ leaf = "border",        enabled = true, speed = 3.5,  bezier = "easeInOutQuart" })
-- hl.animation({ leaf = "windows",       enabled = true, speed = 3,    spring = "easy",        style = "popin 92%" })
-- hl.animation({ leaf = "windowsIn",     enabled = true, speed = 1.2,  spring = "easy",        style = "popin 88%" })
-- hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2,    bezier = "macSmooth", style = "popin 88%" })
-- hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.5,  bezier = "almostLinear" })
-- hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.3,  bezier = "almostLinear" })
-- hl.animation({ leaf = "fade",          enabled = true, speed = 2.5,  bezier = "macSmooth" })
-- hl.animation({ leaf = "layers",        enabled = true, speed = 3,    bezier = "easeInOutQuart" })
-- hl.animation({ leaf = "layersIn",      enabled = true, speed = 2.5,  bezier = "easeInOutQuart", style = "fade" })
-- hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.8,  bezier = "macSmooth", style = "fade" })
-- hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.6,  bezier = "almostLinear" })
-- hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.4,  bezier = "almostLinear" })
-- hl.animation({ leaf = "workspaces",    enabled = true, speed = 2.8,  bezier = "easeInOutQuart", style = "slide" })
-- hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 2.4,  bezier = "macSmooth", style = "slide" })
-- hl.animation({ leaf = "workspacesOut", enabled = true, speed = 2.8,  bezier = "macSmooth", style = "slide" })
-- hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 5,    bezier = "macSmooth" })

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
