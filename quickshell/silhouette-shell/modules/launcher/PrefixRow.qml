pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * One prefix-mode row in the launcher: a leading glyph icon, a title line,
 * the query text, and a right-aligned hint. The three modes — AI (@), command
 * (>) and terminal ($) — share an identical layout; this component keeps it
 * in one place.
 */
Item {
    id: prow

    property real s: 1
    property string glyph: "sparkles"
    property string title: ""
    property string query: ""
    property string hint: ""

    signal clicked()

    visible: prow.title.length > 0
    height: visible ? 44 * s : 0

    Rectangle {
        anchors.fill: parent
        radius: 9 * s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: prow.clicked()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: 12 * s
        anchors.rightMargin: 12 * s

        GlyphIcon {
            id: rowGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 18 * s
            height: 18 * s
            name: prow.glyph
            color: Theme.vermLit
            stroke: 1.7
        }

        Column {
            anchors.left: rowGlyph.right
            anchors.leftMargin: 10 * s
            anchors.right: rowHint.left
            anchors.rightMargin: 8 * s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * s

            Text {
                width: parent.width
                text: prow.title
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 13.5 * s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: prow.query
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * s
                elide: Text.ElideRight
            }
        }

        Text {
            id: rowHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: prow.hint
            color: Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 11 * s
        }
    }
}
