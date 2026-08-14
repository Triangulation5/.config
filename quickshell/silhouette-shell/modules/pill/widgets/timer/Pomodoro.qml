pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.layout

/**
 * 砂 TIMER — a pomodoro countdown built around a large canvas-drawn circular
 * dial (the same 270° flame-gradient arc as the System surface's CPU/GPU
 * dials). The remaining time sits centred inside the ring so the dial is the
 * first thing the eye lands on. Session toggle, presets and custom time steppers
 * sit below a hairline; Start/Reset buttons close the card. The tick survives
 * surface close and a finished timer plays a chime + posts a desktop
 * notification.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 14

    /** Timer state: "idle", "running", "paused", or "finished". */
    property string timerState: "idle"
    /** Session colour scheme: "focus" (flame-orange) or "break" (teal). */
    property string sessionType: "focus"
    property int totalSecs: 25 * 60
    property int remainingSecs: 25 * 60

    readonly property real progress: totalSecs > 0 ? (totalSecs - remainingSecs) / totalSecs : 0
    readonly property int hours: Math.floor(remainingSecs / 3600)
    readonly property int mins: Math.floor((remainingSecs % 3600) / 60)
    readonly property int secs: remainingSecs % 60
    readonly property int totalHours: Math.floor(totalSecs / 3600)
    readonly property bool running: timerState === "running"
    readonly property bool showCountdown: running || timerState === "paused" || timerState === "finished"

    readonly property string display: {
        var h = Math.floor(remainingSecs / 3600);
        var m = Math.floor((remainingSecs % 3600) / 60);
        var s = remainingSecs % 60;
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    readonly property string durationLabel: {
        var h = Math.floor(totalSecs / 3600);
        var m = Math.floor((totalSecs % 3600) / 60);
        var s = totalSecs % 60;
        if (h > 0) { if (s > 0) return h + "h " + m + "m " + s + "s"; if (m > 0) return h + "h " + m + "m"; return h + "h"; }
        if (s > 0) return m + "m " + s + "s";
        return m + "m";
    }

    readonly property string subline: timerState === "finished" ? "Complete"
        : (running ? "remaining" : (timerState === "paused" ? "paused" : durationLabel))

    readonly property bool focusSession: sessionType === "focus"
    readonly property color accent: focusSession ? Theme.vermLit : "#4ec9b0"
    readonly property color accentGlow: focusSession ? Theme.flameGlow : "#52d1b8"
    readonly property color accentBurn: focusSession ? Theme.vermBurn : "#2a9d8f"

    readonly property var presets: focusSession
        ? [{ label: "25m", secs: 25 * 60 }, { label: "45m", secs: 45 * 60 }, { label: "60m", secs: 60 * 60 }]
        : [{ label: "5m",  secs: 5 * 60  }, { label: "15m", secs: 15 * 60 }, { label: "30m", secs: 30 * 60 }]

    function setDuration(secs) {
        root.totalSecs = Math.max(1, Math.min(86400, secs));
        root.remainingSecs = root.totalSecs;
        root.timerState = "idle";
    }

    function isPresetActive(secs) { return root.totalSecs === secs; }

    function toggle() {
        if (root.timerState === "running") { root.timerState = "paused"; }
        else if (root.timerState === "idle" || root.timerState === "paused") {
            if (root.remainingSecs <= 0) root.remainingSecs = root.totalSecs;
            root.timerState = "running";
        }
    }

    function reset() { root.remainingSecs = root.totalSecs; root.timerState = "idle"; }

    function finish() { root.timerState = "finished"; chimeProc.running = true; notifProc.running = true; }

    Process { id: chimeProc; command: ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"] }
    Process { id: notifProc; command: ["notify-send", "-a", "SilhouetteShell", "Timer finished", "Your " + root.durationLabel + " timer is done.", "-u", "normal"] }

    Timer {
        id: tick
        interval: 1000; repeat: true
        running: root.timerState === "running"
        onTriggered: { if (root.remainingSecs > 0) root.remainingSecs--; if (root.remainingSecs <= 0) root.finish(); }
    }


    /** Ring geometry, shared by Canvas and Ame. */
    readonly property real ringCx: ringArea.width / 2
    readonly property real ringCy: ringArea.height / 2
    readonly property real ringR: Math.min(ringArea.width, ringArea.height) / 2 - (ringLw / 2) - root.s

    readonly property real ringLw: ringArea.width * 0.048
    readonly property real ringStart: 135 * Math.PI / 180
    readonly property real ringFull: 270 * Math.PI / 180

    /** Arc-head angle (radians from 3 o'clock), for the Ame seam dot. */
    readonly property real arcAngle: {
        void root.progress;
        return ringStart + ringFull * Math.max(0, Math.min(1, root.progress));
    }

    readonly property point arcHead: {
        void root.ringCx; void root.ringCy; void root.ringR;
        var ax = ringCx + ringR * Math.cos(arcAngle);
        var ay = ringCy + ringR * Math.sin(arcAngle);
        return ringArea.mapToItem(root, ax, ay);
    }

    ameForm: root.showCountdown ? "seam" : (root.open ? "soul" : "off")
    amePoint: root.showCountdown ? arcHead : timerHeader.soulPoint(root)

    implicitHeight: content.implicitHeight


    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SurfaceHeader {
            id: timerHeader
            kanji: "砂"
            label: "TIMER"
            badge: root.timerState === "running" ? "RUNNING"
                : (root.timerState === "paused" ? "PAUSED"
                : (root.timerState === "finished" ? "DONE" : root.durationLabel))
            badgeColor: root.timerState === "running" ? accentGlow
                : (root.timerState === "finished" ? accent : Theme.dim)
            s: root.s
        }

        Item { width: 1; height: 16 * root.s }

        Item {
            id: ringArea
            width: parent.width * 0.62
            height: width
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                id: ring
                anchors.fill: parent
                antialiasing: true

                property real sweep: 0
                onSweepChanged: ring.requestPaint()
                Behavior on sweep { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

                Component.onCompleted: ring.sweep = root.progress * ringFull
                /** Drive the eased sweep from progress so the ring animates smoothly. */
                Connections {
                    target: root
                    function onProgressChanged() { ring.sweep = root.progress * ringFull; }
                }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var cx = width / 2;
                    var cy = height / 2;
                    var lw = root.ringLw;
                    var r = Math.min(width, height) / 2 - lw / 2 - root.s;
                    var start = root.ringStart;
                    var full = root.ringFull;

                    /** Track ring in threadBg, round caps. */
                    ctx.lineCap = "round";
                    ctx.lineWidth = lw;
                    ctx.strokeStyle = Theme.threadBg;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, start, start + full, false);
                    ctx.stroke();

                    /** Progress arc gradient: accentBurn → accent, same diagonal as Sysmon dials. */
                    var sweep = ring.sweep;
                    if (sweep > 0.01) {
                        var diag = r * 0.7071;
                        var grad = ctx.createLinearGradient(cx - diag, cy + diag, cx + diag, cy - diag);
                        grad.addColorStop(0, root.accentBurn);
                        grad.addColorStop(0.35, root.accentBurn);
                        grad.addColorStop(1, root.accent);
                        ctx.strokeStyle = grad;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, start, start + sweep, false);
                        ctx.stroke();
                    }
                }
            }

            /** Time display centred inside the ring. */
            Column {
                anchors.centerIn: parent
                /** Optical centre nudged up since the ring gap is at the bottom. */
                anchors.verticalCenterOffset: -12 * root.s
                spacing: 5 * root.s

                Text {
                    id: hero
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.display
                    color: root.timerState === "finished" ? accent
                        : (root.running ? accentGlow : Theme.cream)
                    font.family: Theme.font
                    font.pixelSize: root.hours > 0 ? ringArea.width * 0.16 : ringArea.width * 0.20
                    font.weight: Font.ExtraBold
                    font.letterSpacing: -0.004 * ringArea.width
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.showCountdown
                    text: root.subline
                    color: root.timerState === "finished" ? accent
                        : (root.running ? accentGlow : Theme.subtle)
                    font.family: Theme.font
                    font.pixelSize: ringArea.width * 0.058
                    font.weight: Font.DemiBold
                }
            }
        }

        Item { width: 1; height: ringArea.width * 0.087 }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: root.showCountdown ? 0 : implicitHeight
            visible: !root.showCountdown
            spacing: 0

            Rectangle {
                width: Math.max(parent.width * 0.34, focusChip.implicitWidth + 24 * root.s)
                height: 26 * root.s
                radius: 13 * root.s
                color: root.focusSession ? root.accentBurn : "transparent"
                border.width: root.focusSession ? 0 : 1
                border.color: Theme.frameBorder
                z: root.focusSession ? 1 : 0

                Text {
                    id: focusChip
                    anchors.centerIn: parent
                    text: "Focus"
                    color: root.focusSession ? Theme.cream : Theme.dim
                    font.family: Theme.font; font.pixelSize: 11 * root.s; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.sessionType = "focus"
                }
            }

            Rectangle {
                width: Math.max(parent.width * 0.34, breakChip.implicitWidth + 24 * root.s)
                height: 26 * root.s
                radius: 13 * root.s
                color: !root.focusSession ? root.accentBurn : "transparent"
                border.width: !root.focusSession ? 0 : 1
                border.color: Theme.frameBorder
                x: -4 * root.s
                z: !root.focusSession ? 1 : 0

                Text {
                    id: breakChip
                    anchors.centerIn: parent
                    text: "Break"
                    color: !root.focusSession ? Theme.cream : Theme.dim
                    font.family: Theme.font; font.pixelSize: 11 * root.s; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.sessionType = "break"
                }
            }
        }

        Item { width: 1; height: 10 * root.s }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: root.showCountdown ? 0 : implicitHeight
            visible: !root.showCountdown
            spacing: parent.width * 0.02

            Repeater {
                model: root.presets

                Rectangle {
                    required property var modelData
                    readonly property bool active: root.isPresetActive(modelData.secs)
                    width: presetText.implicitWidth + parent.width * 0.06
                    height: 24 * root.s
                    radius: 12 * root.s
                    color: active ? Qt.alpha(root.accentGlow, 0.12) : Theme.frameBg
                    border.width: active ? 1 : 0
                    border.color: active ? Qt.alpha(root.accentGlow, 0.22) : "transparent"

                    Text {
                        id: presetText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: active ? root.accentGlow : Theme.subtle
                        font.family: Theme.font; font.pixelSize: 11 * root.s; font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDuration(modelData.secs)
                    }
                }
            }
        }

        Hairline {
            s: root.s
            height: root.showCountdown ? 0 : 1
            visible: !root.showCountdown
        }

        Column {
            width: parent.width
            height: root.showCountdown ? 0 : implicitHeight
            visible: !root.showCountdown
            topPadding: ringArea.width * 0.065
            spacing: ringArea.width * 0.043

            component TimeRow: Item {
                id: row
                width: parent ? parent.width : 0
                height: vText.implicitHeight
                property string label: ""
                property int value: 0
                property real step: 1

                Text {
                    anchors.left: parent.left
                    anchors.baseline: vText.baseline
                    text: row.label
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8 * root.s
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "−"
                        color: minusArea.containsMouse ? Theme.bright : Theme.faint
                        font.family: Theme.font; font.pixelSize: ringArea.width * 0.075; font.weight: Font.Medium
                        MouseArea {
                            id: minusArea
                            anchors.fill: parent; anchors.margins: -4 * root.s
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDuration(root.totalSecs - row.step)
                        }
                    }
                    Text {
                        id: vText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "" + row.value
                        color: Theme.cream
                        font.family: Theme.font; font.pixelSize: ringArea.width * 0.066; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                        horizontalAlignment: Text.AlignRight; width: parent.parent.width * 0.12
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "+"
                        color: plusArea.containsMouse ? Theme.bright : Theme.faint
                        font.family: Theme.font; font.pixelSize: ringArea.width * 0.075; font.weight: Font.Medium
                        MouseArea {
                            id: plusArea
                            anchors.fill: parent; anchors.margins: -4 * root.s
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDuration(root.totalSecs + row.step)
                        }
                    }
                }
            }

            TimeRow { label: "Hours";   value: root.totalHours; step: 3600 }
            TimeRow { label: "Minutes"; value: Math.floor((root.totalSecs % 3600) / 60); step: 60 }
            TimeRow { label: "Seconds"; value: root.totalSecs % 60; step: 1 }
        }

        Item { width: 1; height: root.showCountdown ? ringArea.width * 0.043 : ringArea.width * 0.065 }

        Item {
            width: parent.width
            height: 32 * root.s

            Row {
                anchors.centerIn: parent
                spacing: parent.width * 0.04

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? parent.parent.width * 0.11 : 0; height: 28 * root.s; radius: 14 * root.s
                    color: Theme.frameBg; border.width: 1; border.color: Theme.frameBorder
                    visible: root.showCountdown || root.totalSecs !== root.remainingSecs; clip: true
                    Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

                    GlyphIcon {
                        anchors.centerIn: parent; width: 13 * root.s; height: 13 * root.s
                        name: "return"; color: Theme.dim; stroke: 2
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.reset() }
                }

                Rectangle {
                    id: startBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.parent.width * 0.55, startLabel.implicitWidth + parent.parent.width * 0.16); height: 28 * root.s; radius: 14 * root.s
                    color: root.running ? Qt.alpha(accent, 0.10) : (root.timerState === "finished" ? accentBurn : accent)
                    border.width: root.running ? 1 : 0
                    border.color: root.running ? Qt.alpha(accent, 0.18) : "transparent"
                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        id: startLabel; anchors.centerIn: parent
                        text: root.running ? "Pause" : (root.timerState === "finished" ? "Restart" : "Start")
                        color: root.running ? accentGlow : Theme.cream
                        font.family: Theme.font; font.pixelSize: ringArea.width * 0.066; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (root.timerState === "finished") { root.reset(); root.toggle(); } else root.toggle(); }
                    }
                }
            }
        }

        Item { width: 1; height: root.showCountdown ? 0 : 8 * root.s }

        /** Keyboard hint: a spacebar keycap glyph instead of the word, then the R reset hint. */
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.timerState === "idle"
            spacing: 5 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -0.5 * root.s
                width: 18 * root.s
                height: 14 * root.s
                name: "space"
                color: Theme.faint
                stroke: 1.8
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "start · r reset"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                font.letterSpacing: 0.4 * root.s
            }
        }
    }
}
