pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.services
import qs.modules.controlcenter
import qs.components.controls

/**
 * Shadow settings group: enable toggle, range, and render power.
 * Extracted from the monolithic Look surface.
 */
Group {
    id: shadowGrp

    property var look: null

    title: "Shadow"
    s: look ? look.s : 1

    property alias shEnRow: shEnRow
    property alias shRangeRow: shRangeRow
    property alias shRangeScrub: shRangeScrub
    property alias shPowRow: shPowRow
    property alias shPowScrub: shPowScrub

    FieldRow {
        surface: look; id: shEnRow
        label: "Enabled"; caption: "Drop shadow under windows"; icon: "cloud"
        LinkToggle {
            s: look.s
            on: look.shadowOn
            onToggled: {
                look.shadowOn = !look.shadowOn;
                look.writeShadow("enabled", look.shadowOn ? "true" : "false");
            }
        }
    }

    FieldRow {
        surface: look; id: shRangeRow
        label: "Range"; caption: "How far the shadow spreads"; icon: "scaling"
        collapsed: !look.shadowOn
        ScrubValue {
            id: shRangeScrub; s: look.s
            value: look.shadowRange; openValue: look.base.shadowRange
            from: 0; to: 50; step: 1; unit: "px"
            onEdited: v => { look.shadowRange = v; look.writeShadow("range", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: shPowRow
        label: "Render power"; caption: "Shadow falloff sharpness"; icon: "bolt"
        collapsed: !look.shadowOn
        ScrubValue {
            id: shPowScrub; s: look.s
            value: look.shadowRenderPower; openValue: look.base.shadowRenderPower
            from: 1; to: 4; step: 1
            onEdited: v => { look.shadowRenderPower = v; look.writeShadow("render_power", String(v)); }
        }
    }
}
