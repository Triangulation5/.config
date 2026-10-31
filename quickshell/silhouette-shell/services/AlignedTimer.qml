import QtQuick

/**
 * A Timer that fires on wall-clock boundaries rather than on a fixed phase.
 *
 * A plain `Timer { interval: 1000; repeat: true }` keeps whatever phase it
 * happened to start with, so a clock driven by it shows the time as of its last
 * tick: anywhere from a few milliseconds to almost a whole period behind the
 * real clock, and a second is occasionally skipped or doubled as that phase
 * drifts across a boundary. For a 60 s timer the same fault leaves a date or an
 * hour label up to a minute stale.
 *
 * This one re-reads the wall clock on every fire and arms itself for just past
 * the next boundary, so the delay always comes from the time actually read. It
 * keeps what the shell's plain-Timer clocks were chosen for: nothing is
 * scheduled further ahead than one period, so after a locked session or a late
 * wake it re-reads the clock the instant the event loop runs again instead of
 * freezing one tick behind (the failure mode of a SystemClock).
 *
 *     AlignedTimer {
 *         period: 1000
 *         onTick: (date) => root.now = date
 *     }
 *
 * `tick` carries the Date that was read, so a handler uses it directly instead
 * of calling `new Date()` a moment later and landing on the other side of a
 * boundary. It fires once as soon as the timer starts, so a consumer is never
 * left holding the value from construction.
 */
Timer {
    id: root

    /** Boundary to align to, in ms. Must divide 60000: 1000 is every whole
     *  second, 60000 every whole minute. */
    property int period: 1000
    /** Slack past the boundary, so a wake a hair early cannot read the clock
     *  just before it and show the previous second. */
    property int margin: 10
    /** False stops the timer; true starts it, with an immediate tick. */
    property bool active: true

    signal tick(var date)

    property bool _ready: false

    repeat: false
    running: false

    function fire() {
        const d = new Date();
        const period = Math.max(1, root.period);
        const phase = (d.getSeconds() * 1000 + d.getMilliseconds()) % period;
        /** Arm before emitting, so a handler that throws cannot leave the timer dead. */
        root.interval = period - phase + root.margin;
        root.restart();
        root.tick(d);
    }

    onTriggered: root.fire()

    onActiveChanged: {
        if (!root._ready)
            return;
        if (root.active)
            root.fire();
        else
            root.stop();
    }

    onPeriodChanged: {
        if (root._ready && root.active)
            root.fire();
    }

    Component.onCompleted: {
        root._ready = true;
        if (root.active)
            root.fire();
    }
}
