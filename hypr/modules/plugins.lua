hl.config { plugin = { dynamic_cursors = {
    enabled = true,

    mode = "none",

    threshold = 2,

    rotate = {
        length = 20,
        offset = 0.0,
    },
    tilt = {
        limit = 5000,
        activation = "negative_quadratic",
        window = 100,
        full = 60,
    },
    stretch = {
        limit = 3000,
        activation = "quadratic",
        window = 100,
    },

    shake = {
        enabled = true,
        threshold = 5,

        base = 3.5,

        speed = 2.0,

        influence = 0.0,

        limit = 5.0,

        timeout = 900,

        effects = false,

        ipc = false,
    },

    hyprcursor = {
        nearest = 0,
        enabled = true,
        resolution = -1,
        fallback = "clientside",
    },
}}}
