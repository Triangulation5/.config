pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services
import qs.modules.bar

/**
 * Workspace tags: one number per workspace on this monitor, the active one
 * blocked. The lit tag is a flat accent block with the digit in the ink that
 * reads on it — dwm's own blocked tag, squared off rather than rounded — and the
 * idle tags are bare dim numbers beside it. Display only — no click handler,
 * because the bar is not a control surface.
 *
 * Every tag keeps the block's padding even though only the lit one draws, so the
 * digits hold their places when the active workspace changes instead of the row
 * shuffling as the block moves; that is also why the row's own spacing is tight,
 * since each tag already carries its padding.
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

    /** Tight: each tag carries a block's own padding on either side of the digit. */
    spacing: 2 * s

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

        /**
         * A chip squared off into dwm's tag block. An idle tag passes a
         * transparent fill rather than none, which still counts as the chip being
         * on — that is what reserves its padding so the row never shifts.
         */
        delegate: Chip {
            required property var modelData

            readonly property bool lit: String(modelData) === root.activeName

            s: root.s
            radius: 0
            fill: lit ? BarStyle.accent : "transparent"
            edge: "transparent"

            Text {
                text: modelData
                color: lit ? BarStyle.accentInk : BarStyle.dim
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: lit ? Font.DemiBold : Font.Normal
            }
        }
    }
}
