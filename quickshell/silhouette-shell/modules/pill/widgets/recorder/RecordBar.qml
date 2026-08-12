pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.services
import qs.components.icons
import qs.components.controls
import qs.modules.pill.widgets

/**
 * The Recorder's full-width flame action bar plus the in-surface source
 * chooser: the Start / countdown / Stop face and the Screen · Window/Region
 * picker with its monitor sub-chooser. Owns its own chooser state and keyboard
 * focus; the actions go out as signals (press, source/monitor pick) so the
 * host runs the ScreenRec flow.
 */
Item {
    id: bar

    property real s: 1.1
    property bool counting: false
    property int countdown: 0
    property bool recording: false
    property var monitors: []

    /** Exposed so the host can map the Ame anchor to the record dot. */
    property alias recDot: recDot

    signal pressRequested()
    signal sourcePicked(string kind)
    signal monitorPicked(string name)

    property bool chooserOpen: false
    property bool screenChooserOpen: false
    property int chooserFocus: -1
    property int monFocus: -1

    readonly property int monCount: monitors.length

    /** Flips the source chooser; opening clears any monitor sub-chooser. */
    function toggleChooser() {
        bar.chooserOpen = !bar.chooserOpen;
        bar.screenChooserOpen = false;
    }

    /** The screen tile was picked with several monitors: open the sub-chooser. */
    function openMonitorChooser() {
        bar.screenChooserOpen = true;
    }

    function closeChoosers() {
        bar.chooserOpen = false;
        bar.screenChooserOpen = false;
    }

    /**
     * Reset chooser state for a surface open/close cycle: choosers close and
     * the keyboard focus re-arms (0) when opening, or goes dormant (-1) when
     * the surface leaves.
     */
    function reset(active) {
        bar.closeChoosers();
        bar.chooserFocus = active ? 0 : -1;
        bar.monFocus = active ? 0 : -1;
    }

    /**
     * Keyboard focus inside the inline source chooser: 0 = Screen, 1 = Window /
     * Region; once the monitor sub-chooser is open it walks the monitor tiles
     * instead. Returns true when a chooser consumed the move.
     */
    function chooserMove(dir) {
        if (!bar.chooserOpen)
            return false;
        if (bar.screenChooserOpen) {
            if (monCount === 0)
                return false;
            if (bar.monFocus < 0 || bar.monFocus >= monCount)
                bar.monFocus = 0;
            bar.monFocus = (bar.monFocus + dir + monCount) % monCount;
            monList.positionViewAtIndex(bar.monFocus, ListView.Contain);
            return true;
        }
        if (bar.chooserFocus < 0 || bar.chooserFocus > 1)
            bar.chooserFocus = 0;
        bar.chooserFocus = (bar.chooserFocus + dir + 2) % 2;
        return true;
    }

    /** Return on the inline source chooser: pick the focused tile. */
    function chooserActivate() {
        if (!bar.chooserOpen)
            return false;
        if (bar.screenChooserOpen) {
            if (bar.monFocus >= 0 && bar.monFocus < monCount)
                bar.monitorPicked(monitors[bar.monFocus].name);
            return true;
        }
        var idx = bar.chooserFocus < 0 ? 0 : bar.chooserFocus;
        bar.sourcePicked(idx === 0 ? "screen" : "window");
        return true;
    }

    /**
     * Backspace on the inline source chooser: the monitor sub-chooser returns
     * to the source tiles, the source tiles close the chooser. Returns true
     * when a chooser consumed it.
     */
    function chooserBack() {
        if (!bar.chooserOpen)
            return false;
        if (bar.screenChooserOpen) {
            bar.screenChooserOpen = false;
            return true;
        }
        bar.chooserOpen = false;
        return true;
    }

    /** Tile click path (MonTile drives this through its `surface`); emits out. */
    function pickMonitor(name) {
        bar.monitorPicked(name);
    }

    width: parent.width
    height: 44 * bar.s

    Rectangle {
        id: actionBar
        anchors.fill: parent
        radius: 14 * bar.s
        clip: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: bar.recording ? Qt.alpha(Theme.verm, 0.34) : Qt.alpha(Theme.verm, 0.2) }
            GradientStop { position: 1.0; color: bar.recording ? Qt.alpha(Theme.verm, 0.16) : Qt.alpha(Theme.flameGlow, 0.09) }
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: actionBar.radius
            color: "transparent"

            Rectangle {
                id: cdFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                visible: bar.counting
                width: parent.width * (bar.counting && Flags.recordCountdown > 0
                    ? (Flags.recordCountdown - bar.countdown + 1) / Flags.recordCountdown : 0)
                color: Qt.alpha(Theme.vermLit, 0.18)
                Behavior on width { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
            }
        }

        Rectangle {
            id: recDot
            anchors.left: parent.left
            anchors.leftMargin: 18 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            visible: !bar.counting && !bar.recording
            width: 17 * bar.s
            height: 17 * bar.s
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.vermLit }
                GradientStop { position: 1.0; color: Theme.vermDeep }
            }
        }

        Rectangle {
            id: stopSquare
            anchors.left: parent.left
            anchors.leftMargin: 18 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.recording
            width: 15 * bar.s
            height: 15 * bar.s
            radius: 4 * bar.s
            color: Theme.vermLit
            SequentialAnimation on scale {
                running: bar.recording
                loops: Animation.Infinite
                NumberAnimation { to: 1.08; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        Text {
            id: cdNumber
            anchors.left: parent.left
            anchors.leftMargin: 20 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.counting
            text: bar.countdown
            color: Theme.flameGlow
            font.family: Theme.font
            font.pixelSize: 24 * bar.s
            font.weight: Font.ExtraBold
            font.features: { "tnum": 1 }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: bar.counting ? 46 * bar.s : 47 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            text: bar.recording ? "Stop recording"
                : (bar.counting ? "Starting…" : "Start recording")
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 13 * bar.s
            font.weight: Font.Bold
            font.letterSpacing: 0.5 * bar.s
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 18 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            text: bar.counting ? "tap to cancel" : "tap"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * bar.s
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: bar.pressRequested()
        }
    }

    Rectangle {
        id: chooser
        anchors.fill: parent
        visible: bar.chooserOpen
        radius: 14 * bar.s
        color: Theme.cardBot
        border.width: 1
        border.color: Theme.border

        MouseArea {
            anchors.fill: parent
            onClicked: bar.chooserOpen = false
        }

        Row {
            anchors.fill: parent
            anchors.margins: 6 * bar.s
            spacing: 6 * bar.s

            Repeater {
                model: [
                    { kind: "screen", label: "Screen", glyph: "monitor" },
                    { kind: "window", label: "Window / Region", glyph: "video" }
                ]

                Rectangle {
                    id: srcTile
                    required property var modelData
                    required property int index
                    readonly property bool focused: !bar.screenChooserOpen && bar.chooserFocus === index
                    width: (chooser.width - 12 * bar.s - 6 * bar.s) / 2
                    height: parent.height
                    radius: 9 * bar.s
                    color: srcArea.containsMouse || srcTile.focused ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                    border.width: 1
                    border.color: srcArea.containsMouse || srcTile.focused ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    HoverHandler {
                        onHoveredChanged: if (hovered) bar.chooserFocus = index
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8 * bar.s

                        GlyphIcon {
                            width: 16 * bar.s
                            height: 16 * bar.s
                            name: srcTile.modelData.glyph
                            color: srcArea.containsMouse ? Theme.vermLit : Theme.iconDim
                            stroke: 1.7
                        }
                        Text {
                            height: 16 * bar.s
                            verticalAlignment: Text.AlignVCenter
                            text: srcTile.modelData.label
                            color: srcArea.containsMouse ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11 * bar.s
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: srcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bar.sourcePicked(srcTile.modelData.kind)
                    }
                }
            }
        }
    }

    Rectangle {
        id: screenChooser
        anchors.fill: parent
        visible: bar.screenChooserOpen
        radius: 14 * bar.s
        color: Theme.cardBot
        border.width: 1
        border.color: Theme.border

        MouseArea {
            anchors.fill: parent
            onClicked: bar.screenChooserOpen = false
        }

        ListView {
            id: monList
            anchors.fill: parent
            anchors.margins: 6 * bar.s
            anchors.rightMargin: 22 * bar.s
            orientation: ListView.Horizontal
            spacing: 6 * bar.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: bar.monitors

            delegate: MonTile {
                required property var modelData
                required property int index
                surface: bar
                s: bar.s
                monName: modelData.name
                monW: modelData.w
                monH: modelData.h
                rowIndex: index
            }
        }

        WheelScroller {
            flick: monList
            s: bar.s
            anchors.fill: monList
        }

        GlyphIcon {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 7 * bar.s
            width: 12 * bar.s
            height: 12 * bar.s
            name: "chevron-left"
            color: backArea.containsMouse ? Theme.cream : Theme.faint
            stroke: 2

            MouseArea {
                id: backArea
                anchors.fill: parent
                anchors.margins: -7 * bar.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    bar.screenChooserOpen = false;
                    bar.chooserOpen = true;
                }
            }
        }
    }
}
