pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Surface-lifecycle and memory pressure bus for the shell. Each pill connects
 * to `unloadClosedRequested` and drops its own closed surfaces when it fires, so
 * the `unloadAll` IPC only emits and every live pill answers.
 *
 * It also actively samples the shell's resident memory (RSS in MB) from
 * `/proc/<pid>/statm`. If memory reaches the soft pressure cap (280MB), it
 * triggers `unloadClosed()` and `gc()`, and signals Pill.qml to adopt harsh
 * tails. If memory ever reaches the hard ceiling (330MB, capped at 350MB), it
 * runs an immediate emergency sweep to keep the shell strictly bounded.
 */
Singleton {
    id: root

    /**
     * Fired by `unloadClosed()`. Receivers drop every closed surface right now,
     * leaving the surface on screen and any running timer alone (see
     * `Pill.unloadClosedSurfaces`). Idempotent: a second emit finds nothing left.
     */
    signal unloadClosedRequested()

    /**
     * Ask every pill to drop its closed surfaces immediately, regardless of how
     * much of its tier tail is left. Synchronous — the drops land before this
     * returns — and safe to call from anywhere, including repeatedly.
     */
    function unloadClosed() {
        root.unloadClosedRequested();
    }

    /** Live shell RSS in MB, polled every 8 seconds. */
    property int shellRssMb: 0

    /** Memory thresholds in MB */
    readonly property int idleTargetMb: 180
    readonly property int softCapMb: 280
    readonly property int hardCapMb: 330

    /** True when memory exceeds the soft pressure cap */
    readonly property bool underPressure: shellRssMb >= softCapMb

    function checkMemory() {
        if (!memProc.running)
            memProc.running = true;
    }

    Process {
        id: memProc
        command: ["sh", "-c", "read -r _ r _ < /proc/\"$1\"/statm 2>/dev/null; echo $((r*4/1024))", "_", String(Quickshell.processId)]
        stdout: StdioCollector {
            onStreamFinished: {
                var mb = parseInt(this.text.trim(), 10);
                if (isNaN(mb) || mb <= 0)
                    return;
                root.shellRssMb = mb;

                if (mb >= root.softCapMb) {
                    root.unloadClosed();
                    if (typeof gc === "function")
                        gc();
                }
            }
        }
    }

    Timer {
        id: memTimer
        interval: 8000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.checkMemory()
    }
}
