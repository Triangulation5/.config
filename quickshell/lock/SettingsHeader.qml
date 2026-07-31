import QtQuick
import "Singletons"

/**
 * Settings surface header bar.
 */
Item {
    id: head

    property real s: 1
    property string title: "SETTINGS"
    property bool showBack: false
    signal backClicked()

    width: parent ? parent.width : 0
    height: 24 * head.s

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * head.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * head.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * head.s
        }
    }

    GlyphIcon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * head.s
        height: 16 * head.s
        name: head.showBack ? "chevron-left" : "cog"
        color: Theme.iconDim
        stroke: head.showBack ? 2.2 : 1.7

        MouseArea {
            anchors.fill: parent
            enabled: head.showBack
            cursorShape: Qt.PointingHandCursor
            onClicked: head.backClicked()
        }
    }
}
