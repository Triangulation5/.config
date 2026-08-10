-- https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 1,

        col = {
            active_border   = { colors = { "rgba(205, 205, 205, 0.15)" } },
            inactive_border = "rgba(205, 205, 205, 0.08)",
        },

        resize_on_border = false,
        -- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,
    },

    decoration = {
        rounding       = 10,
        rounding_power = 4,

        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        shadow = {
            enabled      = true,
            range        = 20,
            render_power = 3,
            color        = 0xee121212,
        },

        blur = {
            enabled   = true,
            size      = 6,
            passes    = 2, -- 3 for frosted glass
            vibrancy  = 0.17,
            new_optimizations = true,
        },
    },

    animations = {
        enabled = true,
    },
})

-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
local animationStyle = "macos" -- Choose one of: "liquid", "pill", "macos"

if animationStyle == "liquid" then
    -- Liquid motion style
    hl.curve("liquidMorph", { type = "bezier", points = { { 0.20, 1.08 }, { 0.36, 1.00 } } })
    hl.curve("liquidFast",  { type = "bezier", points = { { 0.22, 1.03 }, { 0.40, 1.00 } } })
    hl.curve("liquidFade",  { type = "bezier", points = { { 0.50, 0.50 }, { 0.75, 1.00 } } })

    hl.animation({ leaf = "global",        enabled = true, speed = 5.2, bezier = "liquidMorph"                      })
    hl.animation({ leaf = "windows",       enabled = true, speed = 5.2, bezier = "liquidMorph"                      })
    hl.animation({ leaf = "windowsIn",     enabled = true, speed = 7.0, bezier = "liquidMorph", style = "popin 92%" })
    hl.animation({ leaf = "windowsOut",    enabled = true, speed = 7.0, bezier = "liquidMorph", style = "popin 92%" })
    hl.animation({ leaf = "border",        enabled = true, speed = 1.6, bezier = "liquidFast"                       })
    hl.animation({ leaf = "fade",          enabled = true, speed = 3.0, bezier = "liquidFade"                       })
    hl.animation({ leaf = "fadeIn",        enabled = true, speed = 3.0, bezier = "liquidFade"                       })
    hl.animation({ leaf = "fadeOut",       enabled = true, speed = 3.0, bezier = "liquidFade"                       })
    hl.animation({ leaf = "layers",        enabled = true, speed = 7.0, bezier = "liquidMorph", style = "popin 90%" })
    hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3.0, bezier = "liquidFade"                       })
    hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 3.0, bezier = "liquidFade"                       })
    hl.animation({ leaf = "workspaces",    enabled = true, speed = 2.6, bezier = "liquidMorph", style = "slide"     })
elseif animationStyle == "pill" then
    -- Pill style animations
    hl.curve("pillMorph",      { type = "bezier", points = { { 0.16, 1.00 },    { 0.30, 1.00 } } })
    hl.curve("quick",          { type = "bezier", points = { { 0.15, 0.00 },    { 0.10, 1.00 } } })
    hl.curve("almostLinear",   { type = "bezier", points = { { 0.50, 0.50 },    { 0.75, 1.00 } } })

    hl.animation({ leaf = "global",        enabled = true, speed = 4.2,   bezier = "pillMorph"                        })
    hl.animation({ leaf = "windows",       enabled = true, speed = 4.2,   bezier = "pillMorph"                        })
    hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.2,   bezier = "pillMorph",   style = "popin 92%" })
    hl.animation({ leaf = "windowsOut",    enabled = true, speed = 4.2,   bezier = "pillMorph",   style = "popin 92%" })
    hl.animation({ leaf = "border",        enabled = true, speed = 4.2,   bezier = "quick"                            })
    hl.animation({ leaf = "fade",          enabled = true, speed = 4.2,   bezier = "almostLinear"                     })
    hl.animation({ leaf = "fadeIn",        enabled = true, speed = 4.2,   bezier = "almostLinear"                     })
    hl.animation({ leaf = "fadeOut",       enabled = true, speed = 4.2,   bezier = "almostLinear"                     })
    hl.animation({ leaf = "layers",        enabled = true, speed = 4.2,   bezier = "pillMorph",   style = "popin 90%" })
    hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 4.2,   bezier = "pillMorph"                        })
    hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 4.2,   bezier = "pillMorph"                        })
    hl.animation({ leaf = "workspaces",    enabled = true, speed = 4.2,   bezier = "pillMorph",   style = "slide"     })
elseif animationStyle == "macos" then
    -- macOS Sonoma / VisionOS-inspired fluid motion
    -- Soft ease-in-out, minimal overshoot (2-5%), physical "weight", low GPU cost
    -- General ease: classic macOS-style deceleration curve, no overshoot

    hl.curve("macosEase",     { type = "bezier", points = { { 0.20, 0.06 }, { 0.18, 1.00 } } })
    hl.curve("macosOpen",     { type = "bezier", points = { { 0.28, 1.02 }, { 0.42, 1.00 } } })
    hl.curve("macosClose",    { type = "bezier", points = { { 0.32, 0.00 }, { 0.18, 1.00 } } })
    hl.curve("macosBorder",   { type = "bezier", points = { { 0.28, 0.05 }, { 0.22, 1.00 } } })
    hl.curve("macosFade",     { type = "bezier", points = { { 0.38, 0.00 }, { 0.32, 1.00 } } })
    hl.curve("macosWorkspace", { type = "bezier", points = { { 0.18, 0.90 }, { 0.25, 1.00 } } })

    hl.animation({ leaf = "global",        enabled = true, speed = 4.0, bezier = "macosEase"                            })
    hl.animation({ leaf = "windows",       enabled = true, speed = 4.4, bezier = "macosEase"                            })
    hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.6, bezier = "macosOpen",      style = "popin 98%"  })
    hl.animation({ leaf = "windowsOut",    enabled = true, speed = 5.2, bezier = "macosClose",     style = "popin 96%"  })
    hl.animation({ leaf = "border",        enabled = true, speed = 2.4, bezier = "macosBorder"                          })
    hl.animation({ leaf = "fade",          enabled = true, speed = 3.4, bezier = "macosFade"                            })
    hl.animation({ leaf = "fadeIn",        enabled = true, speed = 3.4, bezier = "macosFade"                            })
    hl.animation({ leaf = "fadeOut",       enabled = true, speed = 3.4, bezier = "macosFade"                            })
    hl.animation({ leaf = "layers",        enabled = true, speed = 4.4, bezier = "macosOpen",      style = "popin 97%"  })
    hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 3.4, bezier = "macosFade"                            })
    hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 3.4, bezier = "macosFade"                            })
    hl.animation({ leaf = "workspaces",    enabled = true, speed = 3.6, bezier = "macosWorkspace", style = "slide"      })
end
