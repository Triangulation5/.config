pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Interactive drill-in header: back chevron on the left, an ALL-CAPS title and
 * an optional status caption, with the panel's own controls in the default
 * right slot. Emits `back()` from the chevron. Geometry is the link drill-ins'
 * standard; the settings sub-view forms (new workspace, new bind, add app)
 * share it so every drill-in reads the same. Height collapses with `visible`,
 * so callers can hide the header without leaving a hole in a Column.
 */
Item {
    id: root

    property real s: 1.1
    property string title: ""
    property string caption: ""
    property color captionColor: Theme.faint
    property real rightInset: 0

    signal back()

    /** The panel's right-side controls. */
    default property alias content: rightSlot.data

    width: parent ? parent.width : 0
    height: visible ? 24 * root.s : 0

    Row {
        id: leftHeader
        anchors.left: parent.left
        anchors.right: rightSlot.left
        anchors.rightMargin: root.rightInset + 8 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * root.s

        Item {
            id: backSlot
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s

            HoverIcon {
                anchors.fill: parent
                name: "chevron-left"
                color: Theme.iconDim
                hoverColor: Theme.cream
                stroke: 1.8
                hitPad: 6 * root.s
                onClicked: root.back()
            }
        }

        Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            textFormat: Text.PlainText
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * root.s
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.caption.length > 0
            text: "· " + root.caption
            textFormat: Text.PlainText
            color: root.captionColor
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
            width: Math.max(0, leftHeader.width - backSlot.width
                - titleText.implicitWidth - leftHeader.spacing * 2)
            elide: Text.ElideRight
        }
    }

    Item {
        id: rightSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
