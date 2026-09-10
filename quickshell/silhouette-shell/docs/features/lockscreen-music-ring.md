# Lockscreen music ring

A ribbon visualizer for the lockscreen that orbits the profile icon while a player is active.

The original intent was a semi-circular bending line over the profile, but it evolved into an orbiting ring of dots with a flowing ribbon line through them. It owns its own cava process so it does not touch the existing lock glow (Cava.lockLevels / GlowField).

## What it does

- Renders a ring of dots around the profile icon while music is playing.
- Draws a ribbon through the dots so the ring reads as a moving band rather than separate dots.
- Dots and ribbon react to cava levels: radius, opacity and color shift with the audio.
- Uses the shell theme tokens (Theme.vermLit, Theme.verm, Theme.flameGlow) so it fits the lock palette instead of bringing its own colors.

## Status

Work in progress. The geometry, cava piping, theme tinting and ribbon path are in place. The ribbon is not reliably showing yet, so this is parked as a work in progress rather than wired in as a finished feature.

## Placement

It lives under `modules/lock/` as its own QML type and is imported through the existing lock module import. It is mounted in `Content.qml` around the profile block and kept off while the clock is expanded or the lock is authenticating.
