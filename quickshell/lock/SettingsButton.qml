pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Collapsed lockscreen settings button: a rounded capsule anchored at the
 * bottom-right corner of the lockscreen surface. Matches existing lockscreen
 * surface styling (Theme.capsule, Theme.capsuleBorder) and exposes expansion
 * animation state (`expanded`, `expandProgress`, `animating`).
 */
Item {
    id: root

    property real s: 1.1
    property bool expanded: false
    readonly property alias expandProgress: expandAnim.value
    readonly property bool animating: expandAnim.running

    signal clicked()

    width: 42 * root.s
    height: 42 * root.s

    QtObject {
        id: expandAnim
        property real value: root.expanded ? 1.0 : 0.0

        Behavior on value {
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: height / 2

        color: mouse.containsMouse ? Qt.alpha(Theme.cream, 0.12) : Theme.capsule
        border.width: 1
        border.color: mouse.containsMouse ? Theme.cream : Theme.capsuleBorder

        scale: mouse.containsPress ? 0.90 : (mouse.containsMouse ? 1.06 : 1.0)
        opacity: 1.0 - (expandAnim.value * 0.90)

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
        Behavior on scale {
            SpringAnimation {
                spring: 4.5
                damping: 0.35
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutQuad
            }
        }

        GlyphIcon {
            id: icon
            anchors.centerIn: parent
            width: 20 * root.s
            height: 20 * root.s

            name: "cog"
            color: mouse.containsMouse || root.expanded ? Theme.cream : Theme.iconDim
            stroke: 1.8

            rotation: (expandAnim.value * 90) + (mouse.containsMouse ? 20 : 0)

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on rotation {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
