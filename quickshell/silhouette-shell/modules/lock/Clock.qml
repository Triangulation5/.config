pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services

/**
 * Lock screen clock. Renders the time (12/24-hour, optional seconds) and date in
 * the Flags-driven formats, plays a lift-and-scale intro on first paint, and
 * reports clockClicked so the main lock can expand into the full date layout.
 *
 * The minimal bar gets the clock without any of its entrance: `still` is on
 * there, and the intro and the OutBack pops are the two things it switches off.
 * The bar's whole character is that it is already there — a strip that sits at the
 * top edge rather than a pill that grows — so a clock that lifts into place and
 * settles with an overshoot reads as the pill shell leaking through into the one
 * surface that is not the pill. What is left is the clock sitting where it sits,
 * with the press feedback still answering a click.
 *
 * The expand morph is untouched: that one is a response to a click rather than an
 * entrance, and a click that does nothing visible is its own bug.
 */

Item {
    id: clock

    property real s: 1.1
    property bool visibleClock: true
    property bool expanded: false
    property real pressScale: 1

    /**
     * The minimal bar's lock: no entrance animation, no overshoot. Named for what
     * it does rather than which flag sets it, so the block below reads as the
     * reason and not as the mechanism.
     */
    readonly property bool still: Flags.barEnabled

    signal clockClicked()

    scale: pressScale

    Behavior on pressScale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    readonly property var weekdays: [
        "Sunday", "Monday", "Tuesday",
        "Wednesday", "Thursday", "Friday", "Saturday"
    ]

    readonly property var months: [
        "January", "February", "March",
        "April", "May", "June",
        "July", "August", "September",
        "October", "November", "December"
    ]

    readonly property string dateText: {
        var d = sysClock.date;
        return weekdays[d.getDay()] + " · " + months[d.getMonth()] + " " + d.getDate();
    }

    readonly property string expandedDateText: {
        var d = sysClock.date;
        return weekdays[d.getDay()] + " · " + months[d.getMonth()] + " " + d.getDate();
    }

    readonly property string timeText: {
        var d = sysClock.date;

        if (!Flags.time12h)
            return Qt.formatDateTime(d, "HH:mm");

        var h = d.getHours() % 12;
        if (h === 0)
            h = 12;

        var m = d.getMinutes();

        return h + ":" + (m < 10 ? "0" : "") + m;
    }

    readonly property string secondsText: {
        var d = sysClock.date;

        if (!Flags.time12h)
            return Qt.formatDateTime(d, "HH:mm:ss");

        var h = d.getHours() % 12;
        if (h === 0)
            h = 12;

        var m = d.getMinutes();
        var s = d.getSeconds();

        return h
            + ":"
            + (m < 10 ? "0" : "")
            + m
            + ":"
            + (s < 10 ? "0" : "")
            + s;
    }

    SystemClock {
        id: sysClock

        precision: clock.expanded || Flags.clockSeconds
            ? SystemClock.Seconds
            : SystemClock.Minutes
    }

    Text {
        id: compactDate

        visible: clock.visibleClock && !clock.expanded

        x: parent.width * 0.055
        y: parent.height * 0.065

        text: clock.dateText

        color: Theme.cream
        opacity: 0.85

        font.family: Theme.font
        font.weight: 600
        font.pixelSize: 12 * clock.s
        font.letterSpacing: 3.85 * clock.s
        font.capitalization: Font.AllUppercase

        /** No pop: still mode holds it at rest scale, so the change is a cut. */
        scale: clock.still || !visible ? 1 : 0.85

        Behavior on opacity {
            NumberAnimation {
                duration: clock.still ? 0 : 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: clock.still ? 0 : 260
                easing.type: Easing.OutBack
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.6
            shadowVerticalOffset: 1
        }
    }

    Text {
        id: expandedDate

        visible: clock.visibleClock && clock.expanded

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.55

        text: clock.expandedDateText

        color: Theme.cream
        opacity: 0.85

        font.family: Theme.font
        font.weight: 600
        font.pixelSize: 15 * clock.s
        font.letterSpacing: 3.85 * clock.s
        font.capitalization: Font.AllUppercase

        /** No pop, as above — the expanded date arrives at rest scale. */
        scale: clock.still ? 1 : (visible ? 1 : 0.8)

        Behavior on opacity {
            NumberAnimation {
                duration: clock.still ? 0 : 220
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: clock.still ? 0 : 320
                easing.type: Easing.OutBack
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.6
            shadowVerticalOffset: 1
        }
    }

    Text {
        id: clockText

        visible: clock.visibleClock

        anchors.horizontalCenter: parent.horizontalCenter

        y: clock.expanded ? parent.height * 0.38 : parent.height * 0.24

        color: Theme.bright

        font {
            family: Theme.font
            weight: 500
            pixelSize: clock.expanded ? 160 * clock.s : 143 * clock.s
        }

        text: clock.expanded || Flags.clockSeconds ? clock.secondsText : clock.timeText

        opacity: 1

        transform: [
            Translate {
                id: clockLift
                y: 0
            },

            Scale {
                id: clockScale

                origin {
                    x: clockText.width / 2
                    y: clockText.height / 2
                }

                xScale: 1
                yScale: 1
            }
        ]

        property bool introPlayed: false

        /**
         * The lift-and-scale entrance, skipped outright in the minimal bar rather
         * than run at duration 0: the intro also fades the clock in from nothing,
         * and a zero-duration fade still costs the frame it is absent for, so the
         * clock would blink rather than simply be there.
         */
        onVisibleChanged: {
            if (visible && !introPlayed) {
                introPlayed = true
                if (!clock.still)
                    clockIntro.restart()
            }
        }

        ParallelAnimation {
            id: clockIntro

            SequentialAnimation {
                NumberAnimation {
                    target: clockLift
                    property: "y"
                    from: 10 * clock.s
                    to: 0
                    duration: 650
                    easing.type: Easing.OutCubic
                }
            }

            SequentialAnimation {
                NumberAnimation {
                    target: clockScale
                    property: "xScale"
                    from: 0.97
                    to: 1
                    duration: 650
                    easing.type: Easing.OutCubic
                }
            }

            SequentialAnimation {
                NumberAnimation {
                    target: clockScale
                    property: "yScale"
                    from: 0.97
                    to: 1
                    duration: 650
                    easing.type: Easing.OutCubic
                }
            }

            SequentialAnimation {
                NumberAnimation {
                    target: clockText
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 550
                easing.type: Easing.OutCubic
            }
        }

        Behavior on font.pixelSize {
            NumberAnimation {
                duration: 550
                easing.type: Easing.OutCubic
            }
        }

        layer {
            enabled: true

            effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.45)
                shadowBlur: 1.5
                shadowVerticalOffset: 3
            }
        }
    }

    Text {
        id: period

        visible: clock.visibleClock && !clock.expanded && Flags.time12h

        anchors.left: clockText.right
        anchors.leftMargin: 13 * clock.s
        anchors.baseline: clockText.baseline

        color: Theme.bright
        opacity: 0.55

        font.family: Theme.font
        font.weight: 600
        font.pixelSize: 37 * clock.s

        text: Qt.formatDateTime(sysClock.date, "AP")

        Behavior on x {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    MouseArea {
        anchors.fill: parent

        onPressed: clock.pressScale = 0.96
        onReleased: clock.pressScale = 1
        onCanceled: clock.pressScale = 1

        onClicked: clock.clockClicked()
    }
}
