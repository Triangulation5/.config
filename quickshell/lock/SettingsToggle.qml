pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Toggle switch component for boolean settings with tactile spring knob animation.
 */
Rectangle {
    id: root

    property real s: 1.1
    property bool checked: false
    signal toggled(bool checked)

    width: 36 * root.s
    height: 20 * root.s
    radius: height / 2

    color: root.checked ? Qt.alpha(Theme.verm, 0.85) : (toggleMouse.containsMouse ? Qt.alpha(Theme.cream, 0.15) : Theme.fieldBg)
    border.width: 1
    border.color: root.checked ? Theme.verm : (toggleMouse.containsMouse ? Theme.cream : Theme.fieldBorder)

    Behavior on color { ColorAnimation { duration: 180 } }
    Behavior on border.color { ColorAnimation { duration: 180 } }

    Rectangle {
        id: knob
        width: 14 * root.s
        height: 14 * root.s
        radius: width / 2

        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - (3 * root.s) : (3 * root.s)

        color: root.checked ? Theme.bright : (toggleMouse.containsMouse ? Theme.cream : Theme.dim)

        Behavior on x {
            SpringAnimation {
                spring: 4.8
                damping: 0.35
            }
        }
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    MouseArea {
        id: toggleMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked;
            root.toggled(root.checked);
        }
    }
}
