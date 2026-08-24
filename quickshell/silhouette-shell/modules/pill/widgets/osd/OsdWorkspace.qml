pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.pill.widgets
import qs.modules.pill.widgets.osd

/**
 * Workspace OSD face: the live workspace dots, centered, click-disabled (the
 * OSD is a passive indicator). Exposes `indicatorWidth` so the Osd root can
 * size the morph to the dot strip.
 */
OsdFace {
    id: face

    property string screenName: ""

    readonly property real indicatorWidth: wsIndicator.implicitWidth

    Workspaces {
        id: wsIndicator
        anchors.centerIn: parent
        screenName: face.screenName
        s: face.s
        gap: 8 * face.s
        enabled: false
    }
}
