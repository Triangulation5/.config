pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls
import qs.components.layout

/**
 * 砂 TIMER — a pomodoro countdown built around a large canvas-drawn circular
 * dial. The dial is the hero: the remaining time sits centred inside it and the
 * arc itself is the countdown, draining from a full ring at the start to an
 * empty one as the session runs. The ring's head is where the flame docks while
 * counting (`ameForm: "seam"`), so the Ame bead rides the shrinking arc.
 *
 * The card reads as two states. Idle, it is a setup sheet: a sliding Focus/Break
 * switch, the session's presets, and hour/minute/second steppers. Counting, that
 * whole sheet folds away — animated, not snapped — so the ring, the running time
 * and the Pause/Reset row own the card. The fold is one `clip`ped container whose
 * height animates on the shared motion language, so the pill body morphs to match
 * it rather than jumping. A finished session leaves the ring lit in the accent
 * with a slow breath behind the "Complete" line.
 *
 * The tick survives surface close (the pill never evicts a running timer) and a
 * finished timer plays a chime and posts a desktop notification.
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

    /**
     * The card's two faces. `showCountdown` is true for every state past the
     * first Start (running, paused, finished); `setupVisible` is its complement,
     * gating the fold of the setup sheet.
     */
    readonly property bool running: timerState === "running"
    readonly property bool showCountdown: running || timerState === "paused" || timerState === "finished"
    readonly property bool setupVisible: !showCountdown

    /**
     * Remaining fraction of the session, clamped so a paused/overrun tick can
     * never paint past the ring. The arc drains with it: 1 = a full ring, 0 = the
     * empty track a finished session leaves behind.
     */
    readonly property real remainingFrac: totalSecs > 0 ? Math.max(0, Math.min(1, remainingSecs / totalSecs)) : 0
    readonly property int hours: Math.floor(remainingSecs / 3600)
    readonly property int totalHours: Math.floor(totalSecs / 3600)

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

    /** Verb the spacebar hint names for the current state. */
    readonly property string hintAction: running ? "pause" : (timerState === "paused" ? "resume" : "start")

    readonly property bool focusSession: sessionType === "focus"
    readonly property color breakLit: "#4ec9b0"
    readonly property color breakGlow: "#52d1b8"
    readonly property color breakBurn: "#2a9d8f"
    readonly property color accent: focusSession ? Theme.vermLit : breakLit
    readonly property color accentGlow: focusSession ? Theme.flameGlow : breakGlow
    readonly property color accentBurn: focusSession ? Theme.vermBurn : breakBurn

    readonly property var presets: focusSession
        ? [{ label: "25m", secs: 25 * 60 }, { label: "45m", secs: 45 * 60 }, { label: "60m", secs: 60 * 60 }]
        : [{ label: "5m",  secs: 5 * 60  }, { label: "15m", secs: 15 * 60 }, { label: "30m", secs: 30 * 60 }]

    function setDuration(secs) {
        root.totalSecs = Math.max(1, Math.min(86400, secs));
        root.remainingSecs = root.totalSecs;
        root.timerState = "idle";
    }

    function isPresetActive(secs) { return root.totalSecs === secs; }

    /**
     * Switch session. The switch is only reachable while idle (the sheet folds
     * away once a session starts), so it lands on that session's first preset —
     * a Break should begin at 5m, not inherit the 45m Focus that was set up.
     */
    function pickSession(v) {
        if (root.sessionType === v)
            return;
        root.sessionType = v;
        root.setDuration(root.presets[0].secs);
    }

    function toggle() {
        if (root.timerState === "running") { root.timerState = "paused"; }
        else if (root.timerState === "idle" || root.timerState === "paused") {
            if (root.remainingSecs <= 0) root.remainingSecs = root.totalSecs;
            root.timerState = "running";
        }
    }

    function reset() { root.remainingSecs = root.totalSecs; root.timerState = "idle"; }

    /** The one action the ring and the primary button share: pause, or restart a finished run. */
    function primaryAction() {
        if (root.timerState === "finished") { root.reset(); root.toggle(); }
        else root.toggle();
    }

    function finish() { root.timerState = "finished"; chimeProc.running = true; notifProc.running = true; }

    Process { id: chimeProc; command: ["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"] }
    Process { id: notifProc; command: ["notify-send", "-a", "SilhouetteShell", "Timer finished", "Your " + root.durationLabel + " timer is done.", "-u", "normal"] }

    Timer {
        id: tick
        interval: 1000; repeat: true
        running: root.timerState === "running"
        onTriggered: { if (root.remainingSecs > 0) root.remainingSecs--; if (root.remainingSecs <= 0) root.finish(); }
    }

    /**
     * Slow breath behind the finished state: it lifts the ring's lit track and
     * the "Complete" line together, so a done timer draws the eye without
     * shouting. Reset the moment the state leaves "finished" so the value can
     * never be left mid-cycle when it is read again.
     */
    property real breath: 0
    SequentialAnimation on breath {
        running: root.timerState === "finished"
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0; duration: 1300; easing.type: Easing.InOutSine }
    }
    onTimerStateChanged: if (root.timerState !== "finished") root.breath = 0

    /** Ring geometry, shared by the Canvas and the Ame seam. */
    readonly property real ringLw: ringArea.width * 0.048
    readonly property real ringStart: 135 * Math.PI / 180
    readonly property real ringFull: 270 * Math.PI / 180

    /** Arc-head centre in surface coords — the Ame dock while counting. */
    readonly property point arcHead: ringArea.mapToItem(root, ringArea.head.x, ringArea.head.y)

    ameForm: root.showCountdown ? "seam" : (root.open ? "soul" : "off")
    amePoint: root.showCountdown ? root.arcHead : timerHeader.soulPoint(root)

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
            badge: root.running ? "RUNNING"
                : (root.timerState === "paused" ? "PAUSED"
                : (root.timerState === "finished" ? "DONE" : root.durationLabel))
            badgeColor: root.running ? root.accentGlow
                : (root.timerState === "paused" ? root.accentBurn
                : (root.timerState === "finished" ? root.accent : Theme.dim))
            s: root.s
        }

        Item { width: 1; height: 16 * root.s }

        Item {
            id: ringArea
            width: parent.width * 0.62
            height: width
            anchors.horizontalCenter: parent.horizontalCenter

            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real r: Math.min(width, height) / 2 - (root.ringLw / 2) - root.s
            /** The arc tip follows the *animated* sweep, so the seam dot never detaches from the drawn arc. */
            readonly property real headAngle: root.ringStart + ring.sweep
            readonly property point head: Qt.point(cx + r * Math.cos(headAngle), cy + r * Math.sin(headAngle))

            /** Soft inner tint on hover: the ring is the primary button, so it should read as one. */
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.80
                height: width
                radius: width / 2
                color: Qt.alpha(root.accent, 0.055)
                opacity: ringHover.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }

            Canvas {
                id: ring
                anchors.fill: parent
                antialiasing: true

                /** Drawn sweep, in radians, chasing the remaining fraction through the motion language. */
                property real sweep: root.remainingFrac * root.ringFull
                onSweepChanged: requestPaint()
                Behavior on sweep { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                Connections { target: root; function onBreathChanged() { ring.requestPaint() } }
                Connections { target: root; function onTimerStateChanged() { ring.requestPaint() } }
                Connections { target: root; function onSessionTypeChanged() { ring.requestPaint() } }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var cx = width / 2;
                    var cy = height / 2;
                    var lw = root.ringLw;
                    var r = Math.min(width, height) / 2 - lw / 2 - root.s;
                    var start = root.ringStart;
                    var full = root.ringFull;

                    ctx.lineCap = "round";
                    ctx.lineWidth = lw;

                    /** Track. A finished session lights it in the accent on the slow breath. */
                    var done = root.timerState === "finished";
                    ctx.strokeStyle = done
                        ? Qt.alpha(root.accent, 0.30 + 0.25 * root.breath)
                        : Theme.threadBg;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, start, start + full, false);
                    ctx.stroke();

                    var sweep = ring.sweep;
                    if (sweep > 0.01) {
                        /** Running: a wide, faint echo behind the arc so the dial reads as alive. */
                        if (root.running) {
                            ctx.save();
                            ctx.lineWidth = lw * 2.3;
                            ctx.strokeStyle = Qt.alpha(root.accentGlow, 0.13);
                            ctx.beginPath();
                            ctx.arc(cx, cy, r, start, start + sweep, false);
                            ctx.stroke();
                            ctx.restore();
                        }

                        /** Progress arc gradient: accentBurn → accent, same diagonal as the Sysmon dials. */
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
                    color: root.timerState === "finished" ? root.accent
                        : (root.running ? root.accentGlow : Theme.cream)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
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
                    opacity: root.timerState === "finished" ? 0.55 + 0.45 * root.breath : 1
                    color: root.timerState === "finished" ? root.accent
                        : (root.running ? root.accentGlow : Theme.subtle)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    font.family: Theme.font
                    font.pixelSize: ringArea.width * 0.058
                    font.weight: Font.DemiBold
                }
            }

            /** The whole dial is the primary button. */
            MouseArea {
                id: ringHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.primaryAction()
            }
        }

        Item { width: 1; height: ringArea.width * 0.085 }

        /**
         * Setup sheet: the Focus/Break switch, presets and duration steppers,
         * folded into an animated `clip`ped container. Collapsing it (on Start)
         * lets the card morph down to the running view instead of snapping, and
         * expanding it (on Reset) is the same motion in reverse.
         */
        Item {
            id: setup
            width: parent.width
            height: root.setupVisible ? setupCol.implicitHeight : 0
            clip: true
            Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            Column {
                id: setupCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 0

                SessionSeg { anchors.horizontalCenter: parent.horizontalCenter }

                Item { width: 1; height: 12 * root.s }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6 * root.s

                    Repeater {
                        model: root.presets

                        Rectangle {
                            required property var modelData
                            readonly property bool active: root.isPresetActive(modelData.secs)
                            width: presetText.implicitWidth + 20 * root.s
                            height: 24 * root.s
                            radius: 12 * root.s
                            color: active ? Qt.alpha(root.accentGlow, 0.14) : Theme.frameBg
                            border.width: 1
                            border.color: active ? Qt.alpha(root.accentGlow, 0.30) : Theme.frameBorder
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

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

                Item { width: 1; height: 14 * root.s }

                Hairline { s: root.s }

                Column {
                    width: parent.width
                    topPadding: 12 * root.s
                    bottomPadding: 2 * root.s
                    spacing: 9 * root.s

                    StepRow { label: "Hours";   value: root.totalHours; stepSize: 3600 }
                    StepRow { label: "Minutes"; value: Math.floor((root.totalSecs % 3600) / 60); stepSize: 60 }
                    StepRow { label: "Seconds"; value: root.totalSecs % 60; stepSize: 1 }
                }
            }
        }

        Item { width: 1; height: (root.setupVisible ? 16 : 18) * root.s }

        Item {
            width: parent.width
            height: 32 * root.s

            Row {
                anchors.centerIn: parent
                spacing: parent.width * 0.04

                /** Reset only earns its place once there is something to reset. */
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 44 * root.s : 0
                    height: 28 * root.s
                    radius: 14 * root.s
                    visible: root.showCountdown || root.totalSecs !== root.remainingSecs
                    color: resetArea.containsMouse ? Theme.frameBg : "transparent"
                    border.width: 1
                    border.color: resetArea.containsMouse ? Theme.frameBorder : Theme.hair
                    Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    GlyphIcon {
                        anchors.centerIn: parent; width: 13 * root.s; height: 13 * root.s
                        name: "return"; color: Theme.dim; stroke: 2
                    }
                    MouseArea { id: resetArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.reset() }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(parent.parent.width * 0.62, startLabel.implicitWidth + parent.parent.width * 0.18)
                    height: 30 * root.s
                    radius: 15 * root.s
                    color: root.running ? Qt.alpha(root.accent, 0.12)
                        : (root.timerState === "finished" ? root.accentBurn : root.accent)
                    border.width: root.running ? 1 : 0
                    border.color: root.running ? Qt.alpha(root.accent, 0.22) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: startLabel
                        anchors.centerIn: parent
                        text: root.running ? "Pause"
                            : (root.timerState === "finished" ? "Restart"
                            : (root.timerState === "paused" ? "Resume" : "Start"))
                        color: root.running ? root.accentGlow : Theme.cream
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        font.family: Theme.font; font.pixelSize: ringArea.width * 0.062; font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.primaryAction()
                    }
                }
            }
        }

        Item { width: 1; height: 8 * root.s }

        /** Keyboard hint: a spacebar keycap glyph instead of the word, then the R reset hint. */
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.timerState !== "finished"
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
                text: root.hintAction + " · r reset"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                font.letterSpacing: 0.4 * root.s
            }
        }
    }

    /**
     * Focus/Break switch: two labels on a shared track with a highlight that
     * slides between them on the motion language, rather than two chips
     * swapping a fill. The knob takes the session accent, so the switch carries
     * the same colour the ring will.
     */
    component SessionSeg: Rectangle {
        id: seg

        readonly property int idx: root.focusSession ? 0 : 1
        readonly property real pad: 2 * root.s
        readonly property real half: (width - 2 * pad) / 2

        width: Math.min(parent ? parent.width : 0, 210 * root.s)
        height: 30 * root.s
        radius: height / 2
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder

        Rectangle {
            id: knob
            y: seg.pad
            height: seg.height - 2 * seg.pad
            width: seg.half
            x: seg.pad + seg.idx * seg.half
            radius: height / 2
            color: Qt.alpha(root.accent, 0.18)
            border.width: 1
            border.color: Qt.alpha(root.accent, 0.34)
            Behavior on x { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        }

        Row {
            anchors.fill: parent
            anchors.margins: seg.pad

            Repeater {
                model: [{ label: "Focus", value: "focus" }, { label: "Break", value: "break" }]

                Item {
                    required property var modelData
                    width: seg.half
                    height: parent.height

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.sessionType === modelData.value ? Theme.cream : Theme.dim
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pickSession(modelData.value)
                    }
                }
            }
        }
    }

    /**
     * One duration stepper: a faint caps label and a compact − value + cluster.
     * The value sits in a fixed-width, centred slot so the two steppers keep
     * their +/− in the same place as the digits change, and the labels line up
     * with the cluster rather than the value Text (a baseline anchor to the
     * nested value would point at a cousin, which Qt refuses).
     */
    component StepRow: Item {
        id: stepRow

        width: parent ? parent.width : 0
        height: Math.max(20 * root.s, valueText.implicitHeight)
        property string label: ""
        property int value: 0
        property int stepSize: 1

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: spin.verticalCenter
            text: stepRow.label
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.8 * root.s
        }

        Row {
            id: spin
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s

            TextHoverLabel {
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                text: "−"
                hoverColor: Theme.bright
                idleColor: Theme.faint
                hitMargins: -5 * root.s
                font.family: Theme.font; font.pixelSize: ringArea.width * 0.075; font.weight: Font.Medium
                onClicked: root.setDuration(root.totalSecs - stepRow.stepSize)
            }
            Text {
                id: valueText
                anchors.verticalCenter: parent.verticalCenter
                text: "" + stepRow.value
                color: Theme.cream
                width: ringArea.width * 0.17
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font; font.pixelSize: ringArea.width * 0.066; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            TextHoverLabel {
                anchors.verticalCenter: parent.verticalCenter
                s: root.s
                text: "+"
                hoverColor: Theme.bright
                idleColor: Theme.faint
                hitMargins: -5 * root.s
                font.family: Theme.font; font.pixelSize: ringArea.width * 0.075; font.weight: Font.Medium
                onClicked: root.setDuration(root.totalSecs + stepRow.stepSize)
            }
        }
    }
}
