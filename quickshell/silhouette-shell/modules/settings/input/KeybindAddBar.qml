pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The dashed "+ add keybind" bar under the keybinds list. Highlights on hover
 * and when the focused row lands on it; a tap opens the host's add form.
 */
Item {
    id: root

    property real s: 1.1
    property var host: null
    property bool focused: false

    width: parent ? parent.width : 0
    height: 38 * root.s
    visible: !root.host.formOpen

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 5 * root.s
        anchors.bottomMargin: 5 * root.s
        radius: 9 * root.s
        color: addArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.1) : "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.vermLit, (addArea.containsMouse || root.focused) ? 0.6 : 0.32)

        Row {
            anchors.centerIn: parent
            spacing: 6 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 14 * root.s
                font.weight: Font.Bold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "add keybind"
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.5 * root.s
            }
        }

        MouseArea {
            id: addArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.host.openAdd()
        }
    }
}
