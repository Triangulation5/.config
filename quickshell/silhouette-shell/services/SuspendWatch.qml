pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One logind monitor for the whole shell, so a multi-monitor setup runs a single
 * dbus-monitor instead of one per consumer. Three signals come out of it and
 * nothing else does:
 *
 *  - `resumed` fires on the wake half of PrepareForSleep — the moment a wall
 *    clock may have jumped (through midnight, NTP correction, manual set) — so
 *    widgets can re-anchor to the new date instead of waiting for their next
 *    tick. The pill's hover calendar strip is the subscriber today.
 *  - `suspending` fires on the sleep half of the same signal: the machine is
 *    about to suspend, which is the last moment the lock can be raised. It
 *    covers the suspends hypridle never sees — a bare `systemctl suspend`, or a
 *    lid close or power key logind handles itself — where hypridle's
 *    before_sleep_cmd never runs at all.
 *  - `lockRequested` fires on `Lock` over the session object, which is
 *    `loginctl lock-session`: what hypridle's before_sleep_cmd calls, and what
 *    any other locker wired to logind asks for. Without a listener that request
 *    stopped at logind and the session stayed exactly as it was.
 *
 * All three ride the one monitor, over two match rules. dbus-monitor prints a
 * signal as a header line followed by its arguments, and the shapes here stay
 * unambiguous without carrying state across lines: `Lock` takes no arguments, so
 * its header alone identifies it, and PrepareForSleep's single boolean is the
 * only argument any of these rules produces — `true` for the sleep half, `false`
 * for the wake.
 *
 * If dbus-monitor is unavailable or dies, subscribers degrade: the calendar to
 * its own periodic rollover check, the lock to whatever else fires it.
 */
Singleton {
    id: root

    signal resumed()
    signal suspending()
    signal lockRequested()

    Process {
        id: sleepMon
        command: ["dbus-monitor", "--system",
            "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
            "type='signal',path='/org/freedesktop/login1',"
            + "interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("member=Lock") >= 0)
                    root.lockRequested();
                else if (line.indexOf("boolean true") >= 0)
                    root.suspending();
                else if (line.indexOf("boolean false") >= 0)
                    root.resumed();
            }
        }
    }
}
