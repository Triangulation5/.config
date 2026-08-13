import QtQuick
import qs.services
import qs.components.icons

/**
 * One connectivity row for the LINK surface: leading glyph, name and status
 * caption on the left, and a right-aligned control slot (toggle, signal or
 * battery filament) with a trailing chevron. `content` is the default slot
 * for the right-side controls. `focused` mirrors the keyboard cursor so the
 * row lights up under both mouse and keys; `rowHovered` reports pointer
 * entry so the host can park its focus seam and sync the keyboard index.
 */
Item {
    id: row

    property real s: 1
    property string icon: ""
    property color iconColor: Theme.iconDim
    property string name: ""
    property string sub: ""
    property color subColor: Theme.dim
    property bool subBold: false
    property bool chevron: true
    property bool focused: false

    signal clicked()
    signal rowHovered(bool hovered)

    default property alias content: contentRow.data

    width: parent ? parent.width : 0
    height: 44 * s

    HoverHandler {
        id: rowHover
        onHoveredChanged: row.rowHovered(hovered)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }

    Rectangle {
        anchors.fill: parent
        radius: 10 * s
        color: (rowHover.hovered || row.focused) ? Theme.frameBg : "transparent"
    }

    GlyphIcon {
        id: rowGlyph
        anchors.left: parent.left
        anchors.leftMargin: 8 * s
        anchors.verticalCenter: parent.verticalCenter
        width: 17 * s
        height: 17 * s
        name: row.icon
        color: row.iconColor
        stroke: 1.7
    }

    Column {
        id: rowText
        anchors.left: rowGlyph.right
        anchors.leftMargin: 11 * s
        anchors.right: contentRow.left
        anchors.rightMargin: 8 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * s

        Text {
            width: parent.width
            text: row.name
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12.5 * s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: row.sub
            color: row.subColor
            font.family: Theme.font
            font.pixelSize: 10 * s
            font.weight: row.subBold ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }
    }

    Row {
        id: contentRow
        anchors.right: rowChevron.left
        anchors.rightMargin: 9 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9 * s
    }

    GlyphIcon {
        id: rowChevron
        anchors.right: parent.right
        anchors.rightMargin: 8 * s
        anchors.verticalCenter: parent.verticalCenter
        width: row.chevron ? 14 * s : 0
        height: 14 * s
        visible: row.chevron
        name: "chevron-right"
        color: Theme.iconDim
        stroke: 1.8
    }
}
