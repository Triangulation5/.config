pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls

/**
 * Launcher window mode: the window result rows with an empty-state message,
 * scrolling inside the surface. Rows resolve their own icons through the host;
 * the host also owns selection and activation.
 */
Item {
    id: root

    property real s: 1.1
    property var host: null

    Text {
        anchors.centerIn: winList
        visible: host.windowActive && host.windowResults.length === 0
        text: host.windowQuery.length ? "No windows match" : "No windows open"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    ListView {
        id: winList
        visible: host.windowActive
        anchors.fill: parent
        spacing: 5 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: host.windowResults.length

        delegate: WindowRow {
            required property int index
            surface: host
            s: root.s
            win: host.windowResults[index]
            selected: host.selectedIndex === index
            resolvedIcon: host.iconForWindow(host.windowResults[index] ? host.windowResults[index].cls : "")
        }
    }

    WheelScroller {
        anchors.fill: winList
        visible: host.windowActive
        s: root.s
        flick: winList
    }
}
