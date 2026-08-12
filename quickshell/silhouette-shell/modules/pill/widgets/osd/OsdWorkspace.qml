pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.pill.widgets

/**
 * Workspace OSD face: the live workspace dots, centered, click-disabled (the
 * OSD is a passive indicator). Exposes `indicatorWidth` so the Osd root can
 * size the morph to the dot strip.
 */
Item {
    id: face

    property real s: 1.1
    property string screenName: ""
    property bool active: false

    readonly property real indicatorWidth: wsIndicator.implicitWidth

    opacity: face.active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Workspaces {
        id: wsIndicator
        anchors.centerIn: parent
        screenName: face.screenName
        s: face.s
        gap: 8 * face.s
        enabled: false
    }
}
