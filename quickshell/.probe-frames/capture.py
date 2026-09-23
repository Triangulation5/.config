#!/usr/bin/env python3
"""Probe: capture the pill band across a wallpaper-surface close.

Puts the shell in slow motion via Flags.motionSpeed (flags.json, watchChanges),
opens the wallpaper surface through the pill IPC, then grabs frames of the pill
band with grim while firing the close mid-burst. Every frame is stamped with the
request time so the close can be aligned in the analysis step.
"""
import json, os, subprocess, sys, time

STATE = os.path.expanduser("~/.local/state/silhouette/flags.json")
GEO = sys.argv[1] if len(sys.argv) > 1 else "520,0 880x210"
OUT = sys.argv[2] if len(sys.argv) > 2 else "run1"
PRETRIG = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
TOTAL = float(sys.argv[4]) if len(sys.argv) > 4 else 2.6
SPEED = os.environ.get("PROBE_SPEED", "0.2")

os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    os.remove(os.path.join(OUT, f))

mon = subprocess.run(["hyprctl", "activeworkspace", "-j"], capture_output=True,
                     text=True, check=True)
mon = json.loads(mon.stdout)["monitor"]

# --- slow motion on -------------------------------------------------------
with open(STATE) as fh:
    doc = json.load(fh)
with open(STATE + ".probe-bak", "w") as fh:
    json.dump(doc, fh, indent=4)
doc["motionSpeed"] = float(SPEED)
with open(STATE, "w") as fh:
    json.dump(doc, fh, indent=4)
time.sleep(1.5)

# --- open the strip, let the (slowed) morph land --------------------------
subprocess.run(["qs", "-c", "silhouette-shell", "ipc", "call", "pill", "wallpaper", mon],
               check=True)
time.sleep(7.0)

# --- burst, triggering the close partway through --------------------------
stamps = []
t0 = time.time()
subprocess.Popen(["sh", "-c", "sleep %s; qs -c silhouette-shell ipc call pill hide" % PRETRIG])
i = 0
while time.time() - t0 < TOTAL:
    t = time.time() - t0
    subprocess.run(["grim", "-g", GEO, "-s", "1", "-t", "ppm",
                    os.path.join(OUT, "f%03d.ppm" % i)], check=True)
    stamps.append(t)
    i += 1

with open(os.path.join(OUT, "stamps.json"), "w") as fh:
    json.dump({"stamps": stamps, "pretrig": PRETRIG, "speed": float(SPEED),
               "geo": GEO, "mon": mon}, fh, indent=1)

# --- slow motion off -----------------------------------------------------
doc["motionSpeed"] = 1.0
with open(STATE, "w") as fh:
    json.dump(doc, fh, indent=4)

print("frames:", i, "trigger at", PRETRIG, "s")
print("stamps(ms):", [round(s * 1000) for s in stamps])
