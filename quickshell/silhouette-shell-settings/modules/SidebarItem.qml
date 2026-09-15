import QtQuick
import QtQuick.Layouts
import "../config"

Item {
    id: root

    property string label: ""
    property string icon: "\u25CF"
    property bool selected: false
    signal clicked()

    implicitHeight: 45

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        radius: Theme.radiusRow
        color: root.selected
            ? Theme.selected
            : (mouseArea.containsMouse ? Theme.hover : "transparent")

        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: root.selected ? Qt.rgba(0.616, 0.8, 0.604, 0.35)
                                      : Qt.rgba(0.616, 0.8, 0.604, 0.15)
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    color: Theme.accent
                    font.pixelSize: 13
                }
            }

            Text {
                text: root.label
                color: root.selected ? Theme.text : Theme.textSecondary
                font.pixelSize: Theme.fontSizeNormal
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: Theme.animNormal } }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
