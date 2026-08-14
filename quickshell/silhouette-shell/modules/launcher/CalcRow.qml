pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Launcher calc result row: a framed card showing the evaluated expression and
 * its display value, copied to the clipboard on click (or on Enter from the
 * field). Shown only while the query parses as a real calculation.
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    visible: host.calcActive
    height: visible ? 44 * root.s : 0

    Rectangle {
        anchors.fill: parent
        radius: 9 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: host.copyResult()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 12 * root.s
        anchors.rightMargin: 12 * root.s

        Column {
            anchors.left: parent.left
            anchors.right: copyHint.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * root.s

            Text {
                width: parent.width
                text: "= " + host.calc.display
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 15 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: host.query
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                elide: Text.ElideRight
            }
        }

        Text {
            id: copyHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: host.calcCopied ? "copied" : "↵ copy"
            color: host.calcCopied ? Theme.dim : Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }
    }
}
