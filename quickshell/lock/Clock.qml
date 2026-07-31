pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "Singletons"

Item {
    id: clock

    property real s: 1.1
    property bool visibleClock: true
    property bool expanded: false
    property real pressScale: 1

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

        if (Flags.dateFormat === "2026-07-30")
            return Qt.formatDateTime(d, "yyyy-MM-dd");

        if (Flags.dateFormat === "30/07/2026")
            return Qt.formatDateTime(d, "dd/MM/yyyy");

        if (Flags.dateFormat === "Jul 30, 2026")
            return Qt.formatDateTime(d, "MMM dd, yyyy");

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

        precision: clock.expanded || Flags.showSeconds
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

        scale: visible ? 1 : 0.85

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 260
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

        scale: visible ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 320
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

        y: clock.expanded
            ? parent.height * 0.38
            : parent.height * 0.24

        color: Theme.bright

        font.family: "FiraCode Nerd Font Mono"
        font.weight: 500

        font.pixelSize: clock.expanded
            ? 160 * clock.s
            : 143 * clock.s

        text: clock.expanded || Flags.showSeconds
            ? clock.secondsText
            : clock.timeText

        Behavior on y {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutBack
            }
        }

        Behavior on font.pixelSize {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutBack
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.5)
            shadowBlur: 1
            shadowVerticalOffset: 2
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

        font.family: "FiraCode Nerd Font Mono"
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
