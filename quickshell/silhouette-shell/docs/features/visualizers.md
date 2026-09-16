# Visualizers

## Music bars

The classic cava bars. cava outputs frequency data over a fifo and the shell
renders bars from it in real time. The frame rate is exposed as a flag, so
you can drop it to save CPU on weaker iGPUs.

The capture only runs while the resting pill can actually show the bars, and
the whole cava pipeline shuts down shortly after the pill leaves rest (a
hover, a surface, auto-hide), since the fifo reader is the real cost when
nothing is visible. It also stands down when nothing is playing at all — see
"Every capture answers to the same gate" below.

## Music line

A flowing string instead of bars, from the same idea of cava levels: one cubic
curve per segment through the frequency points, with a soft glow and a colored
dot at each end (`FastMusicLine.qml`). Pick it with the visualizer style flag
(`bars`, `centered`, `string`).

It runs its own cava rather than sharing the bars capture — 10 segments where
the bars take 4 — so `Cava.wanted` stands the bars pipeline down in string mode:
two captures for one visible visualizer would be one too many. The string's own
process follows the bars capture's grace policy: it stays warm while the pill is
away from rest so a quick peek resumes instantly, and is put down after a longer
stretch away (`expandKill`, 5s) when nothing can be looking at it. Frames are
only consumed at rest, so a parked hover or an open surface costs nothing.

## Every capture answers to the same gate

`Cava.clientsPlaying` is true while some stream node that is not one of our own
captures is feeding the graph, and `playbackWanted` follows it through a 4s
grace. The bars capture, the lock glow capture and the string's own cava all
require it.

That is not a CPU saving, it is what keeps the speakers quiet. A monitor capture
holds the sink in its *running* state for as long as it lives, so an analog
output woken by any sound never powers down again while the shell runs — and an
output that stays powered in silence whistles, which reads as a ringing from the
speakers minutes after the music stopped. Measured on the running shell: with a
capture up and no playback the sink read `R` with a 512-frame quantum
indefinitely; releasing the capture put it back to `C` (idle, quantum 0) within
two seconds.

Nothing is lost by gating it: a player opens its stream before its first sample,
so the capture is up by the time sound reaches the sink. Measured on both styles:
no client → no cava process and an idle device; `paplay` a silent file → a cava
process within a beat; the file ends → capture down after the grace, device idle
again. `pipewire-props(7)` has the property for doing this from inside the stream
itself (`node.passive`, so the links don't keep the device busy), but the
captures run through cava's pulse backend, so the gate is the portable answer.
