# Visualizers

## Music bars

The classic cava bars. cava outputs frequency data over a fifo and the shell
renders bars from it in real time. The frame rate is exposed as a flag, so
you can drop it to save CPU on weaker iGPUs.

## Music line

A flowing string instead of bars. It reads the same cava data and animates a
ribbon through the frequency points. Both visualizers only run while the
media bud is visible, and the whole cava pipeline shuts down after the bud
sits idle, since the fifo reader is the real cost when nothing is playing.
