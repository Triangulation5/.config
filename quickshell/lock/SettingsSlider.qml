pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Custom horizontal slider control for numeric adjustments like brightness.
 */
Item {
    id: slider

    property real s: 1.1
    property real value: 0.85
    property real minimumValue: 0.0
    property real maximumValue: 1.0

    signal valueMoved(real value)

    width: 104 * slider.s
    height: 20 * slider.s

    readonly property real fillRatio: (value - minimumValue) / Math.max(0.001, (maximumValue - minimumValue))

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 5 * slider.s
        radius: height / 2
        color: Theme.trackBg

        Rectangle {
            id: fill
            height: parent.height
            width: track.width * Math.max(0, Math.min(1, slider.fillRatio))
            radius: parent.radius
            color: Theme.verm
        }
    }

    Rectangle {
        id: handle
        width: 13 * slider.s
        height: 13 * slider.s
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(slider.width - width, Math.max(0, fill.width - width / 2))

        color: sliderMouse.pressed ? Theme.bright : (sliderMouse.containsMouse ? Theme.cream : Theme.bright)
        border.width: 1
        border.color: sliderMouse.containsMouse ? Theme.verm : Theme.capsuleBorder

        scale: sliderMouse.pressed ? 1.25 : (sliderMouse.containsMouse ? 1.12 : 1.0)
        Behavior on scale {
            SpringAnimation {
                spring: 5.0
                damping: 0.35
            }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: sliderMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function updateValue(mouseEv) {
            var ratio = Math.max(0, Math.min(1, mouseEv.x / slider.width));
            var newVal = slider.minimumValue + ratio * (slider.maximumValue - slider.minimumValue);
            slider.value = newVal;
            slider.valueMoved(newVal);
        }

        onPressed: mouse => updateValue(mouse)
        onPositionChanged: mouse => {
            if (pressed) updateValue(mouse);
        }
    }
}
