pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls

/**
 * Fixed-height scrolling list used by the link surface's drill-ins: a
 * Flickable over the panel's rows, a wheel scroller, an empty-state caption
 * and the same capped height math both panels used. Rows go in the default
 * `rows` slot. `flick` exposes the scroll view so row delegates can keep the
 * keyboard-focused or expanded row in view.
 */
Item {
    id: root

    property real s: 1.1
    property string emptyText: ""
    property bool listEmpty: false
    property real listMaxH: 200 * root.s
    property real listMinH: 24 * root.s
    property bool listHidden: false

    /** Row list content: the panel's Repeater. */
    default property alias rows: listCol.data

    /** The scroll view, for delegates' scroll-into-view. */
    readonly property alias flick: listFlick

    height: root.listHidden ? 0
        : Math.min(Math.max(listCol.implicitHeight, root.listMinH), root.listMaxH)

    Text {
        anchors.centerIn: parent
        visible: root.listEmpty
        text: root.emptyText
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    Flickable {
        id: listFlick
        anchors.fill: parent
        visible: !root.listEmpty
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: listCol
            width: listFlick.width
            spacing: 2 * root.s
        }
    }

    /**
     * Keeps a row delegate in view when the list overflows its fixed-height
     * frame. `mapToItem` gives viewport coords, so scroll by the deficit
     * against the visible bounds.
     */
    function ensureVisible(item) {
        if (!item)
            return;
        var y = item.mapToItem(root.listFlick, 0, 0).y;
        var h = item.height;
        if (y < 0)
            root.listFlick.contentY += y;
        else if (y + h > root.listFlick.height)
            root.listFlick.contentY += y + h - root.listFlick.height;
    }

    WheelScroller {
        anchors.fill: parent
        s: root.s
        flick: listFlick
    }
}
