pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * System-vitals backend for the 系 SYSTEM surface. Polls CPU, memory, swap,
 * network, disk and (when a discrete GPU is present) GPU load, temperature and
 * VRAM, exposing them as live properties the surface binds to. Polling only runs
 * while the system surface or Material desktop glance is visible.
 *
 * Polling runs via a long-lived batched helper (utils/sysmon/sysmon_sampler or
 * utils/sysmon/sampler.py) that streams updates over a single persistent process,
 * eliminating periodic shell pipelines and subprocess fork churn. Hardware
 * detection runs once at startup via --detect-only.
 *
 * CPU load is a two-sample delta of /proc/stat (busy vs total jiffies); network
 * rates are a two-sample delta of /proc/net/dev summed over every interface but
 * loopback, divided by the sample interval. CPU temperature resolves to the
 * most accurate hwmon sensor available: AMD Tdie, else Intel "Package id 0",
 * else AMD Tctl, else the first temp1_input. The GPU path resolves to nvidia
 * (nvidia-smi), AMD (sysfs gpu_busy_percent) or none; an Intel-only or
 * GPU-less machine reports `hasGpu` false so the surface drops to two dials and
 * hides the VRAM cell. Disk is the root filesystem's used percent.
 */
Singleton {
    id: root

    property bool open: false
    property bool desktopOpen: false
    readonly property bool active: open || desktopOpen

    property int cpu: 0
    property int cpuTemp: -1

    property bool hasGpu: false
    property string gpuVendor: ""
    property string amdDev: ""
    property int gpu: 0
    property int gpuTemp: -1
    property bool hasVram: false
    property real vramUsedGb: 0
    property real vramTotalGb: 0

    property real memUsedGb: 0
    property real memTotalGb: 0
    property int memPct: 0
    property real swapUsedGb: 0

    property real netDown: 0
    property real netUp: 0

    property int diskPct: 0
    property string uptime: ""

    property string tempPath: ""

    /** Hardware detection runs once; without this, an absent sensor loops it. */
    property bool detected: false

    property real prevCpuTotal: 0
    property real prevCpuIdle: 0
    property real prevRx: 0
    property real prevTx: 0
    property real prevNetTime: 0

    readonly property string samplerBinary: Qt.resolvedUrl("../utils/sysmon/sysmon_sampler").toString().replace(/^file:\/\//, "")
    readonly property string samplerScript: Qt.resolvedUrl("../utils/sysmon/sampler.py").toString().replace(/^file:\/\//, "")

    function handleLine(line) {
        var p = line.trim().split(/\s+/);
        if (p.length === 0 || p[0] === "")
            return;
        var tag = p[0];
        if (tag === "DETECT") {
            if (p[1] === "TEMP" && p.length > 2) {
                root.tempPath = p[2] === "-" ? "" : p.slice(2).join(" ");
            } else if (p[1] === "GPU") {
                if (p[2] === "nvidia") {
                    root.gpuVendor = "nvidia";
                    root.hasGpu = true;
                    root.hasVram = true;
                } else if (p[2] === "amd") {
                    root.gpuVendor = "amd";
                    root.amdDev = p.slice(3, p.length - 1).join(" ");
                    root.hasGpu = true;
                    root.hasVram = p[p.length - 1] === "1";
                } else {
                    root.gpuVendor = "none";
                    root.hasGpu = false;
                    root.hasVram = false;
                }
                root.detected = true;
            }
        } else if (tag === "CPU") {
            var total = parseFloat(p[1]);
            var idle = parseFloat(p[2]);
            if (root.prevCpuTotal > 0) {
                var dt = total - root.prevCpuTotal;
                var di = idle - root.prevCpuIdle;
                root.cpu = dt > 0 ? Math.max(0, Math.min(100, Math.round(100 * (dt - di) / dt))) : 0;
            }
            root.prevCpuTotal = total;
            root.prevCpuIdle = idle;
        } else if (tag === "MEM") {
            var mt = parseFloat(p[1]);
            var ma = parseFloat(p[2]);
            var st = parseFloat(p[3]);
            var sf = parseFloat(p[4]);
            root.memTotalGb = mt / 1048576;
            root.memUsedGb = (mt - ma) / 1048576;
            root.memPct = mt > 0 ? Math.round(100 * (mt - ma) / mt) : 0;
            root.swapUsedGb = (st - sf) / 1048576;
        } else if (tag === "NET") {
            var rx = parseFloat(p[1]);
            var tx = parseFloat(p[2]);
            var now = Date.now();
            var dtNet = (now - root.prevNetTime) / 1000;
            if (root.prevNetTime > 0 && dtNet > 0) {
                root.netDown = Math.max(0, (rx - root.prevRx) / dtNet / 1048576);
                root.netUp = Math.max(0, (tx - root.prevTx) / dtNet / 1048576);
            }
            root.prevRx = rx;
            root.prevTx = tx;
            root.prevNetTime = now;
        } else if (tag === "TMP") {
            root.cpuTemp = p[1] === "-" ? -1 : Math.round(parseFloat(p[1]) / 1000);
        } else if (tag === "GPU_NV") {
            var c = p.slice(1).join(" ").split(",");
            if (c.length >= 4) {
                root.gpu = Math.max(0, Math.min(100, Math.round(parseFloat(c[0]) || 0)));
                root.gpuTemp = Math.round(parseFloat(c[1]) || 0);
                root.vramUsedGb = (parseFloat(c[2]) || 0) / 1024;
                root.vramTotalGb = (parseFloat(c[3]) || 0) / 1024;
            }
        } else if (tag === "GPU_AMD") {
            root.gpu = Math.max(0, Math.min(100, Math.round(parseFloat(p[1]) || 0)));
            root.gpuTemp = Math.round((parseFloat(p[2]) || 0) / 1000);
            root.vramUsedGb = (parseFloat(p[3]) || 0) / 1073741824;
            root.vramTotalGb = (parseFloat(p[4]) || 0) / 1073741824;
        } else if (tag === "DISK") {
            root.diskPct = parseInt(p[1], 10) || 0;
        } else if (tag === "UP") {
            root.uptime = root.fmtUptime(parseInt(p[1], 10) || 0);
        }
    }

    function fmtUptime(sec) {
        var d = Math.floor(sec / 86400);
        var h = Math.floor((sec % 86400) / 3600);
        var m = Math.floor((sec % 3600) / 60);
        var hh = h < 10 ? "0" + h : "" + h;
        var mm = m < 10 ? "0" + m : "" + m;
        return "UP " + d + "D " + hh + ":" + mm;
    }

    function primeAll() {
        prevCpuTotal = 0;
        prevRx = 0;
        prevNetTime = 0;
        if (!detected && !detectProc.running)
            detectProc.running = true;
    }

    onActiveChanged: if (active) primeAll()

    Component.onCompleted: detectProc.running = true

    /** One-shot hardware detection run at startup. */
    Process {
        id: detectProc
        command: ["sh", "-c",
            "if [ -x \"$1\" ]; then exec \"$1\" --detect-only; else exec python3 \"$2\" --detect-only; fi",
            "_", root.samplerBinary, root.samplerScript]
        stdout: SplitParser {
            onRead: (line) => {
                root.handleLine(line);
            }
        }
    }

    /** Persistent, long-lived metrics sampler active while surface is visible. */
    Process {
        id: samplerProc
        command: ["sh", "-c",
            "if [ -x \"$1\" ]; then exec \"$1\"; else exec python3 \"$2\"; fi",
            "_", root.samplerBinary, root.samplerScript]
        running: root.active
        stdout: SplitParser {
            onRead: (line) => {
                root.handleLine(line);
            }
        }
    }
}
