pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.components.animation

/**
 * Lock screen battery glance. A compact capsule showing the charge icon and
 * percent expands on click into a card with a large glyph, percentage, and time
 * remaining, sharing the pill's press-scale and expand morphs.
 */

Item {
    id: battery

    property real s: 1.1
    property bool expanded: false
    property real pressScale: 1

    /** Open/close choreography: clear one face before the geometry moves. */
    readonly property int compactFadeMs: 140
    readonly property int openDelayMs: 160
    readonly property int contentFadeMs: 220
    readonly property int closeDelayMs: 240
    readonly property int compactReturnMs: 300

    /**
     * The capsule's geometry target, deliberately separate from `expanded`.
     * Opening waits for the compact face to clear; closing waits for the
     * readout to clear, so the two faces are never on screen together.
     */
    property bool panelOpen: false
    property bool compactShown: true

    readonly property real compactGlyphSize: 17 * s
    readonly property real expandedGlyphSize: 72 * s
    readonly property real expandedGlyphGap: 18 * s
    readonly property real compactGlyphX: 6 * s
    readonly property real compactGlyphY: (batteryRow.height + 8 * s - compactGlyphSize) / 2
    readonly property real expandedGlyphX: (280 * s - (expandedGlyphSize + expandedGlyphGap + batteryInfo.width)) / 2
    readonly property real expandedGlyphY: (105 * s - expandedGlyphSize) / 2

    readonly property string icon: {
        if (Battery.full)
            return "battery-full";
        if (Battery.charging)
            return "battery-charging";
        if (Battery.pct >= 90)
            return "battery-full";
        if (Battery.pct >= 70)
            return "battery-high";
        if (Battery.pct >= 50)
            return "battery-medium";
        if (Battery.pct >= 30)
            return "battery-low";
        if (Battery.low)
            return "battery-warning";
        return "battery-empty";
    }

    readonly property string timeRemaining: {
        if (!Battery.dev)
            return "";
        if (Battery.charging)
            return Battery.hasTime ? (Battery.timeStr + " to full") : "Charging";
        /** Held at a threshold: plugged in, not full — saying "Plugged in" here is the half-truth this replaces. */
        if (Battery.pending)
            return "Held at its charge limit";
        if (Battery.full)
            return "Plugged in";
        if (!Battery.hasTime)
            return "Calculating...";
        return Battery.timeStr + " remaining";
    }

    width: batteryBackground.width
    height: batteryBackground.height
    visible: Battery.dev !== null
    scale: pressScale

    /**
     * Content reveal latch: the card's readout stays hidden for the shared
     * latch delay after the capsule starts expanding, so the numbers don't
     * pop in while the background is still mid-morph. The latch drops the
     * instant the surface collapses, so the readout can clear before the
     * capsule goes down.
     */
    RevealLatch {
        id: infoReveal
        shown: battery.panelOpen && battery.expanded
    }

    onExpandedChanged: {
        if (expanded) {
            closeTimer.stop();
            compactTimer.stop();
            compactShown = false;
            if (!panelOpen)
                openTimer.restart();
        } else {
            openTimer.stop();
            compactTimer.stop();
            if (panelOpen)
                closeTimer.restart();
            else
                compactShown = true;
        }
    }

    Timer {
        id: openTimer
        interval: battery.openDelayMs
        onTriggered: if (battery.expanded) battery.panelOpen = true
    }

    Timer {
        id: closeTimer
        interval: battery.closeDelayMs
        onTriggered: {
            if (!battery.expanded) {
                battery.panelOpen = false;
                compactTimer.restart();
            }
        }
    }

    Timer {
        id: compactTimer
        interval: battery.compactReturnMs
        onTriggered: if (!battery.expanded && !battery.panelOpen) battery.compactShown = true
    }

    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: batteryBackground

        anchors.centerIn: parent

        width: battery.panelOpen
            ? 280 * battery.s
            : batteryRow.width + 12 * battery.s

        height: battery.panelOpen
            ? 105 * battery.s
            : batteryRow.height + 8 * battery.s

        /** Square in dwm style: the desktop has no rounded anything then. */
        radius: BarMode.dwmStyle
            ? 0
            : (battery.panelOpen ? 18 * battery.s : height / 2)

        color: battery.panelOpen ? ColorScheme.capsule : "transparent"

        border.width: battery.panelOpen ? 1 : 0
        border.color: ColorScheme.capsuleBorder

        Behavior on width {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutBack
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutBack
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 260
            }
        }

        Behavior on border.width {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: batteryRow

            anchors.centerIn: parent

            spacing: 7 * battery.s

            opacity: battery.compactShown ? 1 : 0
            scale: battery.compactShown ? 1 : 0.8

            Behavior on opacity {
                NumberAnimation {
                    duration: battery.compactFadeMs
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                }
            }

            /** Reserves the icon slot; the travelling glyph is the only icon. */
            Item {
                anchors.verticalCenter: parent.verticalCenter

                width: battery.compactGlyphSize
                height: battery.compactGlyphSize
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: Battery.pct + "%"

                color: Theme.cream
                opacity: 0.85

                font.family: Theme.font
                font.pixelSize: 12 * battery.s
                font.weight: 600
                font.letterSpacing: 1.3 * battery.s
            }
        }

        /**
         * The readout hangs off the travelling glyph instead of a centred Row,
         * so the gap stays exact while the glyph slides and grows. Only its
         * opacity is latched; it clears before the capsule starts closing.
         */
        Column {
            id: batteryInfo

            anchors.verticalCenter: parent.verticalCenter

            x: chargeGlyph.x + chargeGlyph.width + battery.expandedGlyphGap

            spacing: 4 * battery.s

            opacity: battery.panelOpen && battery.expanded && infoReveal.ready ? 1 : 0
            scale: battery.expanded ? 1 : 0.9
            transformOrigin: Item.Left

            Behavior on opacity {
                NumberAnimation {
                    duration: battery.contentFadeMs
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 360
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                text: Battery.charging ? "Charging" : (Battery.pending ? "On AC" : "Battery")

                color: Theme.cream

                font.family: Theme.font
                font.pixelSize: 14 * battery.s
                font.weight: 600
            }

            Text {
                text: Battery.pct + "%"

                color: Theme.bright

                font.family: Theme.font
                font.pixelSize: 22 * battery.s
                font.weight: 700
            }

            Text {
                text: battery.timeRemaining

                color: Theme.dim

                font.family: Theme.font
                font.pixelSize: 11 * battery.s
                font.weight: 500
            }
        }

        /**
         * One physical glyph, shared by both faces: it rests in the compact
         * icon slot and flies into the card's larger slot as the capsule opens.
         * The spacers in both rows reserve its space; nothing crossfades.
         */
        GlyphIcon {
            id: chargeGlyph

            x: battery.panelOpen ? battery.expandedGlyphX : battery.compactGlyphX
            y: battery.panelOpen ? battery.expandedGlyphY : battery.compactGlyphY

            width: battery.panelOpen ? battery.expandedGlyphSize : battery.compactGlyphSize
            height: width

            name: battery.icon
            color: Theme.cream

            stroke: 1.8
            opacity: battery.panelOpen ? 0.95 : 0.9

            Behavior on x {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.centerIn: parent

        width: parent.width + 30 * battery.s
        height: parent.height + 25 * battery.s

        z: 100

        hoverEnabled: true

        onPressed: battery.pressScale = 0.96
        onReleased: battery.pressScale = 1
        onCanceled: battery.pressScale = 1

        onClicked: battery.expanded = !battery.expanded
    }
}
