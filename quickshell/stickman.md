# Stickman.qml Procedural Animation Specification

<!--toc:start-->
- [Stickman.qml Procedural Animation Specification](#stickmanqml-procedural-animation-specification)
  - [Overview](#overview)
  - [Public API](#public-api)
  - [Behavior](#behavior)
  - [Animation Phases](#animation-phases)
    - [Idle](#idle)
    - [Anticipation](#anticipation)
    - [Unfold](#unfold)
    - [Flight](#flight)
    - [Landing](#landing)
    - [Collapse](#collapse)
  - [Rendering](#rendering)
  - [Skeleton](#skeleton)
  - [Motion Quality](#motion-quality)
  - [Performance](#performance)
  - [Code Quality](#code-quality)
  - [Design Goal](#design-goal)
- [Second Prompt](#second-prompt)
<!--toc:end-->

## Overview

Create a single self-contained QML component named `Stickman.qml` for Qt
6 using `QtQuick` and a `Canvas` renderer. The component should follow
the same architectural quality as a polished shell animation rather than
a toy demo.

The stickman is a tiny white line-drawn character that acts as a living
cursor. It is normally dormant as a small circular dot (about 4–5 px
radius). Whenever its target position changes significantly, it unfolds
into a stickman, travels to the destination, then collapses back into
the dot.

The animation must be entirely procedural. Do not use sprite sheets,
images, SVGs, particles, or frame-by-frame animation. Every pose should
be computed from a small set of animation parameters.

## Public API

``` qml
property point point        // destination
property string state       // "dot" or "hidden"
property real scale
```

## Behavior

-   When `state == "hidden"`, fade out.
-   When becoming visible, appear at the current position as a dot.
-   If the destination moves only a small amount (≈25--30 px), glide as
    a dot.
-   If the destination moves farther, perform the full travel animation.
-   If the destination changes while traveling, continuously bend the
    Bézier curve toward the moving destination without restarting the
    animation.

## Animation Phases

### Idle

-   Small breathing dot.
-   Very subtle scale pulse.

### Anticipation

-   Dot stretches toward the travel direction.
-   Tiny arm begins emerging.
-   Body elongates like elastic.

### Unfold

-   Dot becomes a miniature stick figure.
-   Head grows first.
-   Torso extends.
-   Arms and legs unfold.

### Flight

-   Character flies along a quadratic Bézier.
-   Torso leans into motion.
-   Lead arm points directly toward destination.
-   Trailing arm swings naturally.
-   Legs trail slightly behind.
-   Head tilts with momentum.
-   Entire body stretches proportionally to speed.
-   Motion should feel like diving through the air rather than walking.

### Landing

-   Character compresses slightly.
-   Knees bend.
-   Pointing arm overshoots slightly.
-   Small squash-and-stretch before stopping.

### Collapse

-   Arms fold inward.
-   Legs retract.
-   Torso shrinks.
-   Head becomes the resting dot.
-   Ends in exactly the original idle dot.

## Rendering

-   Draw entirely with Canvas primitives.
-   Use only circles and line segments.
-   White or slightly warm white.
-   Round line caps.
-   Round joins.
-   Consistent stroke thickness.
-   No textures.
-   No images.
-   No SVG.

## Skeleton

-   Head
-   Neck
-   Torso
-   Left arm
-   Right arm
-   Left leg
-   Right leg

Every joint angle should be calculated procedurally from:

-   Travel direction
-   Travel speed
-   Animation progress

Avoid hard-coded pose keyframes wherever possible.

## Motion Quality

-   Use smooth easing.
-   Use squash and stretch.
-   Slight follow-through in limbs.
-   Small overshoot when pointing.
-   Tiny head bob during motion.
-   Secondary motion in arms and legs.
-   No abrupt transitions.

## Performance

-   Repaint only while animating.
-   Idle repaint around 10–15 FPS.
-   Animation repaint at display refresh.
-   Minimize allocations.
-   Keep rendering deterministic.

## Code Quality

-   Well-commented.
-   Separate animation state from rendering.
-   Small helper functions.
-   Named constants instead of magic numbers.
-   Single-file component.
-   Approximately 500–800 lines of clean, production-quality QML.

## Design Goal

The overall personality should resemble a tiny energetic guide that
eagerly points where it is going, flies there with exaggerated cartoon
body language, sticks the landing, then curls back into an unobtrusive
dot.

The motion should evoke classic Disney animation
principles—anticipation, squash, and stretch, follow-through,
overlapping action, arcs, and appeal—while remaining minimal, elegant,
and suitable for a modern desktop shell.

# Second Prompt

It is perfect. Refine `Stickman.qml` into a production-quality animation component.
Use `Ame.qml` as an architectural and animation reference only. Do **not** copy its visuals or implementation directly. Preserve its design philosophy: procedural animation, smooth state transitions, separation of motion and rendering, and efficient repaint behavior.
Improve the animation quality rather than rewriting the component.
Goals:
- Make every movement feel fluid, continuous, and intentional.
- Eliminate any mechanical or robotic motion.
- Increase anticipation, follow-through, overlap, easing, and secondary motion.
- Blend between poses smoothly without abrupt changes.
- Vary body language naturally based on travel distance and speed.
Expand the animation vocabulary with subtle procedural behaviors such as:
- A slightly larger anticipation for long jumps.
- Dynamic squash-and-stretch during launch and landing.
- Arm and leg drag caused by inertia.
- Head inertia and slight delayed rotation.
- Small overshoot before settling.
- Different behavior for short hops versus long flights.
- Tiny mid-flight adjustments as the destination moves.
- A more organic collapse back into the resting state.
The resting state should be as unobtrusive as `Ame.qml`.
- Rest as a tiny glowing bead rather than a visible stickman.
- Very subtle breathing only.
- No distracting idle motion.
- Only unfold into the stickman when movement begins.
- Collapse cleanly back into the bead after landing.
Replace the current white appearance with the warm ember palette used by `Ame.qml`.
- Deep ember core.
- Warm vermilion body.
- Soft orange-red highlights.
- Gentle molten-glass appearance.
- Subtle inner glow.
- Small glossy highlight.
- Keep the stickman minimal and readable.
Maintain procedural rendering using only Canvas primitives.
Preserve performance characteristics:
- Render only while animating.
- Low idle repaint rate.
- No unnecessary allocations.
- No sprites, SVGs, textures, particles, or frame-by-frame animation.
Favor polish over new features. Every change should make the character feel more alive, expressive, and effortless while remaining minimal enough to fit naturally within a desktop shell.
