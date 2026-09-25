pragma ComponentBehavior: Bound

import QtQuick
import "../../../utils/settings/fields.js" as Fields
import qs.modules.settings
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

    /**
     * This group's fields' bounds and steps, from the table shared with the
     * settings app's Look page (utils/settings/fields.js) — see WindowGroup.
     */
    readonly property var meta: ({
        activeOpacity: Fields.get("deco", "activeOpacity"),
        inactiveOpacity: Fields.get("deco", "inactiveOpacity")
    })

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
            from: opGrp.meta.activeOpacity.min; to: opGrp.meta.activeOpacity.max; step: opGrp.meta.activeOpacity.step; decimals: 2
            onEdited: v => { look.activeOpacity = v; look.writeOpacity("active_opacity", v.toFixed(2)); }
        }
    }

    FieldRow {
        surface: look; id: opInactRow
        label: "Inactive window"; caption: "Unfocused window transparency"; icon: "moon"
        ScrubValue {
            id: opInactScrub; s: look.s
            value: look.inactiveOpacity; openValue: look.base.inactiveOpacity
            from: opGrp.meta.inactiveOpacity.min; to: opGrp.meta.inactiveOpacity.max; step: opGrp.meta.inactiveOpacity.step; decimals: 2
            onEdited: v => { look.inactiveOpacity = v; look.writeOpacity("inactive_opacity", v.toFixed(2)); }
        }
    }
}
