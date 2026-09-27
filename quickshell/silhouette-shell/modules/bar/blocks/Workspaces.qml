pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

/**
 * Workspace tags: one number per workspace on this monitor, the active one lit.
 * Bare numbers, no backdrops: the accent on the lit one is the whole signal, and
 * a chip behind it only competes with the readouts beside it. Display only — no
 * click handler, because the bar is not a control surface.
 *
 * The numbers come from Workspacerules.byMonitor, not Quickshell's
 * `Hyprland.workspaces` model, which collapses every workspace onto id 0 on the
 * Hyprland 0.56 pairing (see Workspacerules). The active one is read from the
 * monitor model, the same source the pill's own dots light from.
 */
Row {
    id: root

    property string screenName: ""
    property real s: 1.1

    spacing: 6 * s

    readonly property var range: Workspacerules.byMonitor[screenName] || []

    readonly property string activeName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }

    Repeater {
        model: root.range

        delegate: Text {
            required property var modelData

            readonly property bool lit: String(modelData) === root.activeName

            text: modelData
            color: lit ? BarStyle.accent : BarStyle.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            font.weight: lit ? Font.DemiBold : Font.Normal
        }
    }
}
