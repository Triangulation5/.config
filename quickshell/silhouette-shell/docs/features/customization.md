# Customization

<!--toc:start-->
- [Customization](#customization)
  - [Theme](#theme)
  - [Wallpaper](#wallpaper)
  - [Icons](#icons)
  - [Motion](#motion)
  - [Rounded screen corners](#rounded-screen-corners)
  - [Game mode](#game-mode)
<!--toc:end-->

## Theme

Every surface reads its colors from one shared token set, so a single swap
re-tints the whole shell. There are three palette modes. Static is a port of
the vague.nvim colorscheme, which replaces the warm vermilion theme Ricelin
shipped. Dynamic follows the live wallpaper-derived palette. Manual picks a
hue on a strip and rebuilds the color set from it, with a dark/light choice.
The UI font is configurable and defaults to Inter.

## Wallpaper

A filmstrip over the wallpaper directory, newest first. The focused thumb is
large and fully lit while the neighbors shrink, dim and desaturate, so the
strip reads as depth. Arrow keys and wheel move focus, Enter applies the pick
through wallpaper.sh, and holding Enter deletes it. The strip stays open so
you can keep trying picks.

Dynamic colors come from a snapshot of the current wallpaper, which is what
the dynamic theme mode feeds on.

## Icons

The icon set is hand drawn SVG, not a stock icon pack. The wifi glyph is the
best example: a custom drawn signal icon instead of a generic asset.

## Motion

Animation durations and easings come from a shared motion module, so every
surface moves with the same feel. A reduce-motion switch and game mode both
cut the animation budget when you want less of it.

## Rounded screen corners

A decoration layer draws rounded corners over the screen edges. The rounding
follows the pill state: game mode removes it, notch mode increases it, and
dynamic island mode uses partial rounding.

## Game mode

A performance switch that collapses the pill to a flat strip, disables
animations and extra spacing, and trims visual effects. Useful for games or
when you want the GPU to only do actual work.
