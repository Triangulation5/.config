import QtQuick
import QtQuick.Layouts
import qs.config

/**
 * One matching *setting* under its page in the rail — the row a search found,
 * where SidebarItem is the page itself. It is the same kind of dumb row: a label
 * that reports a click, indented to read as a child of the page above it and
 * without the icon circle, so a page and its hits are never mistaken for
 * siblings.
 *
 * Rows are addressed by their key everywhere (see Pages.rowKey), never by the
 * descriptor object, because a row read back out of the model is a copy.
 */
Item {
    id: root

    property string label: ""

    signal clicked()

    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 46
        anchors.rightMargin: 10
        radius: Theme.radiusRow - 2
        color: mouse.containsMouse ? Theme.hover : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 56
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
