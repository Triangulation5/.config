# Project TODO

## Create Android One UI/Google Pixel like opening animation for screen turnon.

Implement a screen wake-up animation for the shell.

When the display wakes from suspension, capture or reuse a screenshot of the
screen before it was suspended. Then reveal the screen using a circular **grow
transition**, starting from the bottom-center edge and expanding until the
entire screen is visible.

The effect should resemble `awww`'s image grow transition:

```bash
awww img "$pic" \
    --transition-type grow \
    --transition-pos bottom \
    --transition-fps 60 \
    --transition-step 90
```

Requirements:
- Capture the screen before suspension, if technically feasible.
- Display the captured image during wake-up.
- Animate a circular reveal originating from the bottom-center.
- Expand smoothly until the entire screen is revealed.
- Aim for 60 FPS.
- Integrate the animation cleanly into the existing shell and suspension/wake
  lifecycle. This should only be for the user when they select "Sleep" option
  from the power menu then this should happen. It should be quick.
