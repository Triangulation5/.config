#!/usr/bin/env python3
"""Analyze the probe burst: per-frame metrics + a coarse ASCII view of a frame.

PIL only (no numpy in this environment).

Usage: analyze.py <run-dir> [metrics | grid <frame-index>]
"""
import json, os, sys
from PIL import Image, ImageChops, ImageFilter, ImageStat

run = sys.argv[1] if len(sys.argv) > 1 else "run1"
mode = sys.argv[2] if len(sys.argv) > 2 else "metrics"
CELL = int(os.environ.get("CELL", "8"))
meta = json.load(open(os.path.join(run, "stamps.json")))
stamps = meta["stamps"]
frames = sorted(f for f in os.listdir(run)
                if f.endswith(".ppm") and os.path.getsize(os.path.join(run, f)) > 1000)


def load(name):
    return Image.open(os.path.join(run, name)).convert("RGB")


if mode == "metrics":
    prev = None
    print(f"run={run} geo={meta['geo']} speed={meta['speed']} trigger={meta['pretrig']}s "
          f"frames={len(frames)}")
    print(" idx   t(ms) sinceTrig  mean  max  diffMean  changed-pixels bbox")
    for i, f in enumerate(frames):
        im = load(f)
        t = stamps[i] if i < len(stamps) else -1
        st = ImageStat.Stat(im)
        m = sum(st.mean) / 3.0
        mx = max(e[1] for e in st.extrema)
        if prev is None:
            print(f"{i:4d} {t*1000:7.0f} {(t-meta['pretrig'])*1000:9.0f} {m:6.1f} {mx:4d}       -")
        else:
            d = ImageChops.difference(im, prev).convert("L")
            dm = ImageStat.Stat(d).mean[0]
            mask = d.point(lambda v: 255 if v > 24 else 0)
            bb = mask.getbbox()
            n = ImageStat.Stat(mask).sum[0] // 255
            print(f"{i:4d} {t*1000:7.0f} {(t-meta['pretrig'])*1000:9.0f} {m:6.1f} {mx:4d} {dm:8.2f}  {bb} n={n}")
        prev = im
    sys.exit(0)

fi = int(sys.argv[3]) if len(sys.argv) > 3 else 0
f = frames[fi]
im = load(f)
w, h = im.size
gw, gh = w // CELL, h // CELL
small = im.resize((gw, gh), Image.BOX)
# local detail: high-frequency energy, averaged per cell
hf = ImageChops.difference(im.convert("L"),
                           im.convert("L").filter(ImageFilter.GaussianBlur(1.2)))
hfs = hf.resize((gw, gh), Image.BOX)
lum = list(small.convert("L").getdata())
det = list(hfs.getdata())

RAMP = " .:-=+*#%@"
DR = ".=+*#"
print(f"frame {fi} ({f}) t={stamps[fi]*1000:.0f}ms region={meta['geo']} cell={CELL}px grid={gw}x{gh}")
print("brightness:")
for y in range(gh):
    print("".join(RAMP[min(9, lum[y * gw + x] // 26)] for x in range(gw)))
print("detail (0 flat ... 4 busy):")
for y in range(gh):
    print("".join(DR[min(4, det[y * gw + x] // 6)] for x in range(gw)))
