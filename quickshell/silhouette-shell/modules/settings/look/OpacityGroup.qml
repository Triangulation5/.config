pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.components.controls

/**
 * Opacity settings group: active and inactive window transparency.
 * Extracted from the monolithic Look surface.
 */
Group {
    id: opGrp

    property var look: null

    title: "Opacity"
    s: look ? look.s : 1

    property alias opActRow: opActRow
    property alias opActScrub: opActScrub
    property alias opInactRow: opInactRow
    property alias opInactScrub: opInactScrub

    FieldRow {
        surface: look; id: opActRow
        label: "Active window"; caption: "Focused window transparency"; icon: "awake"
        ScrubValue {
            id: opActScrub; s: look.s
            value: look.activeOpacity; openValue: look.base.activeOpacity
            from: 0.5; to: 1.0; step: 0.05; decimals: 2
            onEdited: v => { look.activeOpacity = v; look.writeOpacity("active_opacity", v.toFixed(2)); }
        }
    }

    FieldRow {
        surface: look; id: opInactRow
        label: "Inactive window"; caption: "Unfocused window transparency"; icon: "moon"
        ScrubValue {
            id: opInactScrub; s: look.s
            value: look.inactiveOpacity; openValue: look.base.inactiveOpacity
            from: 0.5; to: 1.0; step: 0.05; decimals: 2
            onEdited: v => { look.inactiveOpacity = v; look.writeOpacity("inactive_opacity", v.toFixed(2)); }
        }
    }
}
