pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * One compact settings line (icon + label + caption + control), shared by the
 * keyboard-heavy settings tabs. At rest it is an icon + label + control row;
 * hovering or keyboard-focusing the row folds its grey caption open below the
 * label so a long tab stays compact by default. `collapsed` drops the whole row
 * to zero height with the same animation, used by rows that depend on a toggle.
 * `surface` wires hover and activation back to the owning settings surface so
 * the soul seam tracks the focused row; scale derives from it (SettingsRow).
 */
Item {
    id: frow

    property var surface: null
    property string label: ""
    property string caption: ""
    property string icon: ""
    property bool collapsed: false
    default property alias control: ctrl.data

    readonly property bool focused: frow.surface ? frow.surface.focusRowItem === frow : false
    readonly property bool expanded: !frow.collapsed && (fhover.hovered || frow.focused)
    readonly property real s: frow.surface ? frow.surface.s : 1
    readonly property real rowH: 30 * frow.s
    readonly property real capH: 14 * frow.s

    width: parent ? parent.width : 0
    height: frow.collapsed ? 0 : (frow.rowH + (frow.expanded ? frow.capH : 0))
    clip: true
    Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    HoverHandler {
        id: fhover
        onHoveredChanged: if (!frow.collapsed && frow.surface) frow.surface.reportRowHover(frow, hovered)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3 * frow.s
        anchors.bottomMargin: 3 * frow.s
        radius: 9 * frow.s
        color: (fhover.hovered || frow.focused) ? Theme.frameBg : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (frow.surface) frow.surface.activateRow(frow)
    }

    GlyphIcon {
        id: rowIcon
        anchors.left: parent.left
        anchors.leftMargin: 9 * frow.s
        anchors.verticalCenter: parent.verticalCenter
        visible: frow.icon.length > 0
        width: 15 * frow.s
        height: 15 * frow.s
        name: frow.icon
        color: frow.focused ? Theme.cream : Theme.subtle
        stroke: 1.8
    }

    Column {
        anchors.left: rowIcon.visible ? rowIcon.right : parent.left
        anchors.leftMargin: 9 * frow.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * frow.s

        Text {
            text: frow.label
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12.5 * frow.s
            font.weight: Font.Medium
        }

        Text {
            visible: frow.expanded && frow.caption.length > 0
            text: frow.caption
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9 * frow.s
            font.weight: Font.Medium
        }
    }

    Item {
        id: ctrl
        anchors.right: parent.right
        anchors.rightMargin: 9 * frow.s
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
