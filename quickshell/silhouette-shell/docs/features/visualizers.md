# Visualizers

## Music bars

The classic cava bars. cava outputs frequency data over a fifo and the shell
renders bars from it in real time. The frame rate is exposed as a flag, so
you can drop it to save CPU on weaker iGPUs.

The capture only runs while the resting pill can actually show the bars, and
the whole cava pipeline shuts down shortly after the pill leaves rest (a
hover, a surface, auto-hide), since the fifo reader is the real cost when
nothing is visible.
