pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The minimal bar's vitals: CPU load and memory use, sampled from /proc on one
 * process and one cadence. The bar is a readout, not a system monitor, so this
 * is deliberately not services/Sysmon.qml — that one carries GPU, disk, network
 * and temperature for the 系 surface and polls every 500ms. Here it is two
 * numbers, two seconds apart, and only while the bar is on screen.
 *
 * CPU is a two-sample delta of /proc/stat (busy vs total jiffies), the same
 * arithmetic Sysmon uses; the first sample only primes the previous values, so
 * the readout is blank for the first tick rather than wrong. Memory is
 * MemTotal/MemAvailable from /proc/meminfo. One shell spawn produces both, so a
 * tick costs a single process rather than one per block.
 *
 * `active` is set by the bar root when the bar is built and cleared when it is
 * torn down, so nothing is polled while the pill is the shell on screen.
 */
Singleton {
    id: root

    /** True while the bar is on screen; the sampler is gated on it. */
    property bool active: false

    /** Sample cadence in ms. Slow enough for a status strip, cheap enough to read. */
    property int intervalMs: 2000

    property int cpu: 0
    property int memPct: 0

    /** Previous /proc/stat jiffies, for the CPU delta. */
    property real prevTotal: 0
    property real prevIdle: 0

    readonly property string samplerRunner: Qt.resolvedUrl("../utils/sysmon/run.sh").toString().replace(/^file:\/\//, "")
    readonly property bool sysmonActive: typeof Sysmon !== "undefined" && Sysmon && Sysmon.active
    readonly property bool shouldRunProc: root.active && !root.sysmonActive

    onShouldRunProcChanged: {
        /** Drop the stale baseline so the first tick after a restart is not a spike. */
        root.prevTotal = 0;
        root.prevIdle = 0;
    }

    onSysmonActiveChanged: {
        if (root.active && root.sysmonActive) {
            root.cpu = Sysmon.cpu;
            root.memPct = Sysmon.memPct;
        }
    }

    Connections {
        target: typeof Sysmon !== "undefined" ? Sysmon : null
        enabled: root.active && root.sysmonActive
        function onCpuChanged() { root.cpu = Sysmon.cpu; }
        function onMemPctChanged() { root.memPct = Sysmon.memPct; }
    }

    Process {
        id: proc
        command: [root.samplerRunner, "--vitals-only", "--interval", String(root.intervalMs)]
        running: root.shouldRunProc
        stdout: SplitParser {
            onRead: (line) => {
                var p = line.trim().split(/\s+/);
                if (p[0] === "CPU") {
                    var total = parseFloat(p[1]);
                    var idle = parseFloat(p[2]);
                    if (root.prevTotal > 0) {
                        var dt = total - root.prevTotal;
                        var di = idle - root.prevIdle;
                        root.cpu = dt > 0 ? Math.max(0, Math.min(100, Math.round(100 * (dt - di) / dt))) : 0;
                    }
                    root.prevTotal = total;
                    root.prevIdle = idle;
                } else if (p[0] === "MEM") {
                    var mt = parseFloat(p[1]);
                    var ma = parseFloat(p[2]);
                    root.memPct = mt > 0 ? Math.round(100 * (mt - ma) / mt) : 0;
                }
            }
        }
        onExited: {
            if (root.shouldRunProc)
                respawnTimer.restart();
        }
    }

    Timer {
        id: respawnTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.shouldRunProc && !proc.running)
                proc.running = true;
        }
    }
}
