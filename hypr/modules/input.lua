hl.config({
    input = {
        kb_layout  = "us",
        kb_options = "caps:escape",

        follow_mouse = 1,

        sensitivity = -0.30, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
        numlock_by_default = false,
        accel_profile = "flat",
        repeat_rate = 25,
        repeat_delay = 600,
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
