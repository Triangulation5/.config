pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One logind sleep/wake monitor for the whole shell. Subscribers (the pill's
 * hover calendar strip) connect to `resumed`, so a multi-monitor setup runs a
 * single dbus-monitor instead of one per pill. The signal fires on the wake
 * half of logind's PrepareForSleep — the moment a wall clock may have jumped
 * (through midnight, NTP correction, manual set) — so widgets can re-anchor to
 * the new date instead of waiting for their next tick. If dbus-monitor is
 * unavailable or dies, subscribers degrade to their own periodic checks.
 */
Singleton {
    id: root

    signal resumed()

    Process {
        id: sleepMon
        command: ["dbus-monitor", "--system",
            "type='signal',path='/org/freedesktop/login1',"
            + "interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("boolean false") >= 0)
                    root.resumed();
            }
        }
    }
}
