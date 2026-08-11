pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Collapsible settings group: a tappable header (the group label plus a
 * chevron) over a body of rows that animates between zero and its content
 * height, so a long tab shows only the group headers until one is opened.
 * `open` is the initial state; tapping the header toggles it. Rows are added
 * as children (the default property) and `s` carries the surface scale.
 */
Column {
    id: grp

    property string title: ""
    property bool open: false
    property real s: 1
    default property alias rows: body.data

    width: parent ? parent.width : 0
    spacing: 0

    Item {
        width: parent.width
        height: gl.implicitHeight

        GroupLabel { id: gl; s: grp.s; text: grp.title }

        GlyphIcon {
            anchors.right: parent.right
            anchors.verticalCenter: gl.verticalCenter
            width: 15 * grp.s
            height: 15 * grp.s
            name: "chevron-down"
            color: Theme.faint
            stroke: 2.0
            rotation: grp.open ? 0 : -90
            Behavior on rotation { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: grp.open = !grp.open
        }
    }

    Item {
        width: parent.width
        height: grp.open ? body.implicitHeight : 0
        clip: true
        Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        Column {
            id: body
            width: parent.width
        }
    }
}
