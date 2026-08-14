# Core Shell

## The pill

The pill is the whole interface. It lives in an overlay layer window that
covers the monitor, so it never gets re-parented or moved by the compositor.
When collapsed it is just the bar. Hovering grows it into a face. Tapping it
opens a surface, which grows out of the pill in place instead of popping up
as a separate panel.

The overlay window carries a mask. While the pill is collapsed the mask is
the pill rect only, so the rest of the screen clicks through to your windows.
Once the pill is expanded or a surface is open the mask clears and the layer
catches clicks, with a backdrop press to dismiss.

A second window below the pill reserves an exclusive zone, so tiled windows
sit under the pill even while a surface is open. Under auto-hide the zone
collapses to zero and the pill floats over windows without shifting them.

## Modes

The pill has a few display modes. `rest` is the collapsed bar. `hover` is the
expanded face. A surface sets the mode to whatever it needs while it is open.

A flag switches the shape between a rounded pill and a notch-style bar with
square top corners. The notch keeps the pill look but pushes the ears out
wider. Game mode collapses everything into a flat strip and disables
animations, extra spacing and visual effects.

## Ame

Ame is the molten glass bead that acts as the pill's caret. It breathes,
moves fluidly between targets and morphs its form based on what it is
pointing at: a soul bead in the rest pill, a ring over the calendar, a dock
on the media playback bar. Surfaces hand it an anchor point so it can fly to
whichever control needs focus.

## The hover face

The expanded pill shows the hover face: a clock that morphs into the media
bud when music plays, the minimized apps row, the tray and a calendar strip.
The face also hands the media bud to the shell for a floating now-playing
bubble when that is more useful than growing the pill.

## Keyboard navigation

The whole shell is keyboard drivable. Arrow keys move through the focused
list or grid, Return activates, Backspace backs out. A vim-keys flag remaps
navigation to h/j/k/l. The keys are routed through a focus scope that only
grabs keyboard focus while the pill is hovered or a surface is open, so idle
keystrokes never get eaten.
