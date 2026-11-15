#!/usr/bin/env python3
"""
Long-lived system metrics sampler for Sysmon.qml.
Batches /proc, /sys, and statvfs reads in a single persistent process,
eliminating periodic shell pipeline and subprocess fork churn.
"""

import glob
import os
import shutil
import subprocess
import sys
import time

def detect_cpu_temp():
    hwmon_dirs = sorted(glob.glob("/sys/class/hwmon/hwmon*"))
    # 1. Tdie
    for h in hwmon_dirs:
        for l in glob.glob(os.path.join(h, "temp*_label")):
            try:
                with open(l, "r") as f:
                    if f.read().strip() == "Tdie":
                        inp = l.replace("_label", "_input")
                        if os.path.exists(inp):
                            return inp
            except OSError:
                pass

    # 2. Package id 0
    for h in hwmon_dirs:
        for l in glob.glob(os.path.join(h, "temp*_label")):
            try:
                with open(l, "r") as f:
                    if f.read().strip() == "Package id 0":
                        inp = l.replace("_label", "_input")
                        if os.path.exists(inp):
                            return inp
            except OSError:
                pass

    # 3. Tctl
    for h in hwmon_dirs:
        for l in glob.glob(os.path.join(h, "temp*_label")):
            try:
                with open(l, "r") as f:
                    if f.read().strip() == "Tctl":
                        inp = l.replace("_label", "_input")
                        if os.path.exists(inp):
                            return inp
            except OSError:
                pass

    # 4. temp1_input
    for h in hwmon_dirs:
        inp = os.path.join(h, "temp1_input")
        if os.path.exists(inp):
            return inp

    return None

def detect_gpu():
    if shutil.which("nvidia-smi"):
        res = subprocess.run(["nvidia-smi", "-L"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode == 0:
            return {"vendor": "nvidia", "dev": None, "has_vram": True}

    for card in sorted(glob.glob("/sys/class/drm/card*")):
        if "-" in os.path.basename(card):
            continue
        dev = os.path.join(card, "device")
        vendor_file = os.path.join(dev, "vendor")
        if os.path.exists(vendor_file):
            try:
                with open(vendor_file, "r") as f:
                    if f.read().strip() == "0x1002" and os.path.exists(os.path.join(dev, "gpu_busy_percent")):
                        has_vram = os.path.exists(os.path.join(dev, "mem_info_vram_total"))
                        return {"vendor": "amd", "dev": dev, "has_vram": has_vram}
            except OSError:
                pass

    return {"vendor": "none", "dev": None, "has_vram": False}

def read_proc_stat():
    try:
        with open("/proc/stat", "r") as f:
            for line in f:
                if line.startswith("cpu "):
                    parts = line.split()
                    if len(parts) >= 9:
                        user = int(parts[1])
                        nice = int(parts[2])
                        system = int(parts[3])
                        idle = int(parts[4])
                        iowait = int(parts[5])
                        irq = int(parts[6])
                        softirq = int(parts[7])
                        steal = int(parts[8])
                        total = user + nice + system + idle + iowait + irq + softirq + steal
                        idle_total = idle + iowait
                        return total, idle_total
    except OSError:
        pass
    return None

def read_proc_meminfo():
    mt, ma, st, sf = 0, 0, 0, 0
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    mt = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    ma = int(line.split()[1])
                elif line.startswith("SwapTotal:"):
                    st = int(line.split()[1])
                elif line.startswith("SwapFree:"):
                    sf = int(line.split()[1])
    except OSError:
        pass
    return mt, ma, st, sf

def read_proc_net():
    rx_total, tx_total = 0, 0
    try:
        with open("/proc/net/dev", "r") as f:
            for i, line in enumerate(f):
                if i < 2:
                    continue
                clean = line.replace(":", " ")
                parts = clean.split()
                if not parts or parts[0] == "lo":
                    continue
                if len(parts) >= 10:
                    rx_total += int(parts[1])
                    tx_total += int(parts[9])
    except OSError:
        pass
    return rx_total, tx_total

def read_disk_pct():
    try:
        st = os.statvfs("/")
        if st.f_blocks > 0:
            used = st.f_blocks - st.f_bavail
            return round((used / st.f_blocks) * 100)
    except OSError:
        pass
    return 0

def read_uptime():
    try:
        with open("/proc/uptime", "r") as f:
            first = f.read().split()[0]
            return int(float(first))
    except (OSError, ValueError, IndexError):
        pass
    return 0

def sample_amd_gpu(dev):
    busy, temp, vu, vt = 0, 0, 0, 0
    try:
        with open(os.path.join(dev, "gpu_busy_percent"), "r") as f:
            busy = int(f.read().strip())
    except (OSError, ValueError):
        pass

    hw_temps = glob.glob(os.path.join(dev, "hwmon", "hwmon*", "temp1_input"))
    if hw_temps:
        try:
            with open(hw_temps[0], "r") as f:
                temp = int(f.read().strip())
        except (OSError, ValueError):
            pass

    try:
        with open(os.path.join(dev, "mem_info_vram_used"), "r") as f:
            vu = int(f.read().strip())
    except (OSError, ValueError):
        pass

    try:
        with open(os.path.join(dev, "mem_info_vram_total"), "r") as f:
            vt = int(f.read().strip())
    except (OSError, ValueError):
        pass

    return busy, temp, vu, vt

def main():
    if "--once" in sys.argv:
        c = read_proc_stat()
        if c:
            print(f"CPU {c[0]} {c[1]}")
        mt, ma, _, _ = read_proc_meminfo()
        print(f"MEM {mt} {ma}")
        sys.stdout.flush()
        return

    detect_only = "--detect-only" in sys.argv
    temp_path = detect_cpu_temp()
    gpu_info = detect_gpu()

    if temp_path:
        print(f"DETECT TEMP {temp_path}", flush=True)
    else:
        print("DETECT TEMP -", flush=True)

    if gpu_info["vendor"] == "amd":
        dev_str = gpu_info["dev"] or ""
        vram_flag = "1" if gpu_info["has_vram"] else "0"
        print(f"DETECT GPU amd {dev_str} {vram_flag}", flush=True)
    elif gpu_info["vendor"] == "nvidia":
        print("DETECT GPU nvidia", flush=True)
    else:
        print("DETECT GPU none", flush=True)

    if detect_only:
        return

    tick = 0
    try:
        while True:
            # Fast metrics (1s)
            c = read_proc_stat()
            if c:
                print(f"CPU {c[0]} {c[1]}")

            mt, ma, st, sf = read_proc_meminfo()
            print(f"MEM {mt} {ma} {st} {sf}")

            rx, tx = read_proc_net()
            print(f"NET {rx} {tx}")

            if temp_path:
                try:
                    with open(temp_path, "r") as f:
                        print(f"TMP {f.read().strip()}")
                except OSError:
                    print("TMP -")
            else:
                print("TMP -")

            # GPU metrics (2s)
            if tick % 2 == 0:
                if gpu_info["vendor"] == "nvidia":
                    res = subprocess.run(
                        ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                         "--format=csv,noheader,nounits"],
                        capture_output=True, text=True
                    )
                    if res.returncode == 0 and res.stdout.strip():
                        print(f"GPU_NV {res.stdout.splitlines()[0].strip()}")
                elif gpu_info["vendor"] == "amd" and gpu_info["dev"]:
                    busy, temp, vu, vt = sample_amd_gpu(gpu_info["dev"])
                    print(f"GPU_AMD {busy} {temp} {vu} {vt}")

            # Slow metrics (5s, plus tick 0)
            if tick % 5 == 0:
                disk = read_disk_pct()
                print(f"DISK {disk}")
                up = read_uptime()
                print(f"UP {up}")

            sys.stdout.flush()
            tick += 1
            time.sleep(1)
    except (BrokenPipeError, KeyboardInterrupt):
        pass

if __name__ == "__main__":
    main()
