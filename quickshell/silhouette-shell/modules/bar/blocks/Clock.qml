import QtQuick
import qs.services

/**
 * The date and time, following the shell's own 12/24-hour and seconds flags.
 * Driven by a plain repeating Timer rather than a SystemClock, the same reason
 * the pill's clock is: a repeating Timer re-reads the wall clock on every fire,
 * so the time self-heals if the event loop was stopped (a locked session, say)
 * instead of freezing one tick behind.
 *
 * Two tones in one run of type: the time takes the strip's reading colour and
 * the date recedes to the muted one, so the eye lands on the hour first. This is
 * the one block on the strip that keeps a second tone on purpose — the clock is
 * what the bar is read for, and the greyed date is what makes the time findable
 * at a glance instead of one equal-weight run of type. The Row lays both halves
 * out, so the block is still a single line to the bar's layout.
 *
 * The date is not optional — a strip read at a glance is as often asked the day
 * as the hour — and it reads `Sep 27 (Sun)` ahead of the time, the weekday in
 * brackets so it never runs into the month and day beside it.
 */
Row {
    id: root

    property real s: 1.1

    property var now: new Date()

    spacing: 6 * s

    readonly property string timeText: Qt.formatTime(root.now,
        (Flags.time12h ? "h:mm AP" : "HH:mm") + (Flags.clockSeconds ? ":ss" : ""))
    /** The day-of-month is `d`, not `dd`: `Sep 7`, never `Sep 07`. */
    readonly property string dateText: (Qt.formatDate(root.now, "MMM d")
        + " (" + Qt.formatDate(root.now, "ddd") + ")")

    Text {
        text: root.dateText
        color: BarStyle.clockDate
        font.family: Theme.font
        font.pixelSize: 12.5 * root.s
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    Text {
        text: root.timeText
        color: BarStyle.clockTime
        font.family: Theme.font
        font.pixelSize: 12.5 * root.s
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }
}
