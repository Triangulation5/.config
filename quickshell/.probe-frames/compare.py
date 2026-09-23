#!/usr/bin/env python3
"""Compare the offscreen probe frames.

The probe window is pillW+120 x pillH+80 with the surface at (60, 40) sized
pillW x pillH, so:
  inside  = (60, 40, 60+pillW, 40+pillH)   the strip's own rect
  outside = the rest of the window          the black margin + pill body
"""
import os
import sys
from PIL import Image, ImageChops, ImageStat

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
US = 0.7333
PW, PH = round(720 * US), round(172 * US)
BOX = (60, 40, 60 + PW, 40 + PH)


def load(name):
    p = os.path.join(OUT, name)
    return Image.open(p).convert("RGB") if os.path.exists(p) else None


def stats(im, box=None):
    r = im.crop(box) if box else im
    st = ImageStat.Stat(r)
    return sum(st.mean) / 3.0, max(e[1] for e in st.extrema)


def outside(im):
    """The window minus the surface rect: the pill body and the black margin."""
    w, h = im.size
    mask = Image.new("L", (w, h), 255)
    mask.paste(0, BOX)
    return Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), im, mask)


def diff(a, b, label):
    if a is None or b is None:
        print(f"  {label}: missing frame")
        return
    d = ImageChops.difference(a, b).convert("L")
    m = ImageStat.Stat(d).mean[0]
    bb = d.point(lambda v: 255 if v > 12 else 0).getbbox()
    print(f"  {label}: meanDiff={m:6.2f}  changedBBox={bb}")


print(f"frames in {OUT}: surface rect {BOX}\n")

ref = load("open_ref.png")
if ref is None:
    sys.exit("no open_ref frame")

print("== reference (open, dissolve layer off) ==")
print(f"  inside mean={stats(ref, BOX)[0]:6.2f} max={stats(ref, BOX)[1]}")
print(f"  outside mean={stats(outside(ref))[0]:6.2f} max={stats(outside(ref))[1]}")

print("\n== the first close frame vs the open reference (layer turns on) ==")
diff(ref, load("layer_0_op1.png"), "open_ref  vs layer_0_op1 (opacity 1)")
diff(ref, load("control_0_op1.png"), "open_ref  vs control_0_op1 (opacity 1, no layer)")

print("\n== ladder ==")
print(f"{'frame':28s} {'inside mean':>11s} {'inside max':>10s} {'outside mean':>12s} {'outside max':>11s}")
for kind in ("layer", "control"):
    print(f"-- {kind} --")
    for f in sorted(os.listdir(OUT)):
        if not f.startswith(kind + "_"):
            continue
        im = load(f)
        i_mean, i_max = stats(im, BOX)
        o_mean, o_max = stats(outside(im))
        print(f"{f:28s} {i_mean:11.2f} {i_max:10d} {o_mean:12.2f} {o_max:11d}")

print("\n== layer vs control at the same opacity (does the layer change the image?) ==")
for f in sorted(os.listdir(OUT)):
    if not f.startswith("layer_"):
        continue
    c = f.replace("layer_", "control_")
    diff(load(f), load(c), f"{f} vs {c}")
