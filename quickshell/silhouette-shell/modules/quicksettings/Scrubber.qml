pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.quicksettings

/**
 * The -/+ numeric stepper for registry rows of type `int`. Shows the current
 * value between the buttons and emits `nudge(dir)`; the owning row stays the
 * single writer of the flag through its bump(), so stepping, bounds-clamping
 * and rounding logic exists in exactly one place.
 */
Rectangle {
    id: scrub

    property real s: 1.1
    property string text: ""
    signal nudge(int dir)

    width: minusBtn.width + valueLabel.implicitWidth + 6 * scrub.s + plusBtn.width + 2 * scrub.s
    height: 22 * scrub.s
    radius: 8 * scrub.s
    color: Theme.frameBg

    component StepButton: Item {
        id: stepBtn

        property int dir: -1
        readonly property bool pressed: tap.pressed
        readonly property bool hov: hovHandler.hovered

        width: 24 * scrub.s
        height: 22 * scrub.s

        HoverHandler { id: hovHandler }

        Rectangle {
            anchors.fill: parent
            radius: 8 * scrub.s
            color: stepBtn.pressed ? Qt.alpha(Theme.onGlow, 0.18)
                : (stepBtn.hov ? Theme.frameBg : "transparent")
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            anchors.centerIn: parent
            text: stepBtn.dir < 0 ? "−" : "+"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 13 * scrub.s
            font.weight: Font.DemiBold
        }

        TapHandler {
            id: tap
            onTapped: scrub.nudge(stepBtn.dir)
        }
    }

    StepButton { id: minusBtn; dir: -1; anchors.left: parent.left }

    Text {
        id: valueLabel
        anchors.centerIn: parent
        text: scrub.text
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 10.5 * scrub.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    StepButton { id: plusBtn; dir: 1; anchors.right: parent.right }
}
