import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config

/**
 * The floating "Reset to Defaults" button, pinned to the bottom-right of the
 * content area on every page. It only reports a click — what "default" means is
 * the host's business (see ContentArea.resetCurrentPage), so the button has no
 * idea which page is open.
 */
Rectangle {
    id: root

    signal clicked()

    implicitWidth: resetRow.implicitWidth + 28
    implicitHeight: 34
    radius: 10
    color: mouse.containsMouse ? Theme.selected : Theme.navButton
    border.width: 1
    border.color: Theme.border
    scale: mouse.pressed ? 0.96 : 1.0

    Behavior on color { ColorAnimation { duration: Theme.animNormal } }
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    RowLayout {
        id: resetRow
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: "\u27F2"
            color: Theme.textSecondary
            font.pixelSize: 14
            rotation: mouse.pressed ? -60 : 0
            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        Text {
            text: "Reset to Defaults"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
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
