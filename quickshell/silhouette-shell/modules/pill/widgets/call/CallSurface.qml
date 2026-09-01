pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.pill.surfaces
import qs.components.animation
import qs.components.icons

/**
 * Call surface, styled after the iPhone Dynamic Island call UI: caller info on
 * the left, the iconic round controls on the right — a red Decline and green
 * Accept while ringing in (with a soft animated waveform), a lone red End
 * while dialing, and Mute + End once connected, over a live mm:ss timer.
 * Reads live call state from [[Calls]]: ModemManager calls drive the modem
 * directly (the ✕ really hangs up), while a web call (WhatsApp Web, Meet…)
 * detected over PipeWire shows the browser app as the caller — Mute still
 * works (it silences the browser's mic stream) and End focuses the browser
 * window, since only ModemManager can truly hang a call up.
 */
PillSurface {
    id: root

    /** Apple call-green for Accept, Apple call-red for Decline/End. */
    readonly property color callGreen: "#34c759"
    readonly property color callRed: "#ff3b30"

    /** Mirrored off [[Calls]] so the view never talks to the modem directly. */
    readonly property string callState: Calls.state
    readonly property bool ringing: Calls.ringing
    readonly property bool active: Calls.active
    readonly property bool webShown: Calls.webShown
    readonly property string caption: root.webShown ? "Browser call" : Calls.caption
    readonly property string timerText: root.webShown ? Calls.webTimerText : Calls.timerText
    readonly property string number: root.webShown ? Calls.webLabel : Calls.number

    readonly property bool muted: root.webShown
        ? Calls.webMuted
        : (typeof Pipewire !== "undefined") && Pipewire.defaultAudioSource
            && Pipewire.defaultAudioSource.audio && Pipewire.defaultAudioSource.audio.muted

    /** Width the right-hand control cluster occupies, for the text column inset. */
    readonly property real controlW: (callState === "ringing-in" ? 46 * 2 + 12
        : (callState === "active" || root.webShown ? 48 + 12 + 40 : 46)) * s

    function toggleMute() {
        if (root.webShown) {
            Calls.toggleWebMute();
            return;
        }
        var src = Pipewire.defaultAudioSource;
        if (src && src.audio)
            src.audio.muted = !src.audio.muted;
    }

    /**
     * One circular island control: solid Apple-colored when it is a primary
     * action (Accept, End), a quiet dark glass circle otherwise (Mute). Glyph
     * is always white, Apple-style. `lit` lets a neutral button glow its
     * accent when active (mute engaged).
     */
    component CallButton: Item {
        id: btn

        property color fill: Qt.rgba(1, 1, 1, 0.12)
        property color accent: "transparent"
        property string glyph: ""
        property real size: 40 * root.s
        property bool lit: false

        signal clicked()

        implicitWidth: btn.size
        implicitHeight: btn.size

        Rectangle {
            id: disc
            anchors.fill: parent
            radius: width / 2
            color: btn.lit ? Qt.alpha(btn.accent, 0.28) : (discArea.containsMouse ? Qt.lighter(btn.fill, 1.25) : btn.fill)
            border.width: btn.lit ? 1.5 : 0
            border.color: btn.lit ? btn.accent : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        GlyphIcon {
            anchors.centerIn: parent
            width: btn.size * 0.44
            height: btn.size * 0.44
            name: btn.glyph
            color: "#ffffff"
        }

        MouseArea {
            id: discArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    /**
     * Animated ringing waveform: five slim bars that swell and relax on
     * staggered durations, iPhone-incoming-call style. Left running only
     * while the surface is actually ringing.
     */
    Row {
        id: wave
        anchors.left: parent.left
        anchors.leftMargin: root.avatarOuter.right + 26 * root.s
        anchors.top: parent.top
        anchors.topMargin: 36 * root.s
        spacing: 4 * root.s
        visible: root.ringing
        height: 14 * root.s

        Repeater {
            model: 5
            delegate: Rectangle {
                id: bar
                required property int index
                readonly property real base: wave.height
                readonly property real peak: wave.height * [0.9, 0.5, 1.0, 0.65, 0.8][index]
                width: 3 * root.s
                height: base
                radius: width / 2
                color: (root.callState === "ringing-out" || root.callState === "dialing")
                    ? Qt.alpha(root.callRed, 0.75) : Qt.alpha(root.callGreen, 0.85)

                SequentialAnimation {
                    running: root.ringing
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: bar; property: "height"; to: bar.peak
                        duration: 560 + bar.index * 140
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: bar; property: "height"; to: bar.base
                        duration: 560 + bar.index * 140
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    /** Caller avatar: a quiet dark circle with the handset, Apple unknown-caller style. */
    Rectangle {
        id: avatarOuter
        anchors.left: parent.left
        anchors.leftMargin: 22 * root.s
        anchors.verticalCenter: parent.verticalCenter
        width: 64 * root.s
        height: 64 * root.s
        radius: width / 2
        color: Qt.alpha(Theme.cream, 0.10)
        border.width: 1
        border.color: Theme.hair
        GlyphIcon {
            anchors.centerIn: parent
            width: 30 * root.s
            height: 30 * root.s
            name: "phone"
            color: Theme.cream
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.avatarOuter.width + 46 * root.s
        anchors.right: parent.right
        anchors.rightMargin: root.controlW + 60 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5 * root.s

        Text {
            text: root.caption
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6 * root.s
            textFormat: Text.PlainText
        }

        Marquee {
            width: parent.width
            text: root.number.length > 0 ? root.number : "Unknown"
            color: Theme.cream
            pixelSize: 19 * root.s
            weight: Font.DemiBold
            active: root.open
        }

        Text {
            visible: root.active
            text: root.timerText
            color: Theme.cream
            font.family: Theme.fontJp
            font.pixelSize: 18 * root.s
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: 22 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12 * root.s

        CallButton {
            visible: root.callState === "ringing-in"
            fill: root.callRed
            glyph: "phone-hangup"
            size: 46 * root.s
            onClicked: Calls.hangup()
        }

        CallButton {
            visible: root.callState === "ringing-in"
            fill: root.callGreen
            glyph: "phone"
            size: 46 * root.s
            onClicked: Calls.accept()
        }

        CallButton {
            visible: root.callState === "ringing-out" || root.callState === "dialing"
            fill: root.callRed
            glyph: "phone-hangup"
            size: 46 * root.s
            onClicked: Calls.hangup()
        }

        CallButton {
            visible: root.active
            accent: root.callRed
            glyph: root.muted ? "mic-off" : "mic"
            lit: root.muted
            onClicked: root.toggleMute()
        }

        CallButton {
            visible: root.active
            fill: root.callRed
            glyph: "phone-hangup"
            size: 48 * root.s
            /** Modem: hang up for real. Web: bring the browser forward so the call is one click from over. */
            onClicked: root.webShown ? Calls.focusWebCall() : Calls.hangup()
        }
    }
}