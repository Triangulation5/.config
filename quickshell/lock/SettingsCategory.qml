import QtQuick
import "Singletons"

/**
 * Section category header label for grouping settings rows.
 */
Item {
    id: root

    property real s: 1.1
    property string title: ""

    width: parent ? parent.width : 0
    height: 26 * root.s

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12 * root.s
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4 * root.s

        text: root.title
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 9 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }
}
