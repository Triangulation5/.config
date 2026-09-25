pragma ComponentBehavior: Bound

import QtQuick
import "../../../utils/settings/fields.js" as Fields
import qs.modules.settings
import qs.modules.controlcenter
import qs.components.controls

/**
 * Window decoration group: inner/outer gaps, corner rounding, border size, resize
 * mode, and tiling layout. Extracted from the monolithic Look surface so each
 * settings tab stays under 500 lines. The host binds `look` to the owning surface.
 */
Group {
    id: winGrp

    /** Reference to the Look surface for scale and writeDeco / writeOpacity. */
    property var look: null

    title: "Window"
    s: look ? look.s : 1
    open: true

    /**
     * This group's fields' bounds and steps, from the table shared with the
     * settings app's Look page (utils/settings/fields.js). Stated once there and
     * read here, so a range cannot be widened in one UI and not the other.
     */
    readonly property var meta: ({
        gapsIn: Fields.get("deco", "gapsIn"),
        gapsOut: Fields.get("deco", "gapsOut"),
        rounding: Fields.get("deco", "rounding"),
        roundingPower: Fields.get("deco", "roundingPower"),
        borderSize: Fields.get("deco", "borderSize")
    })

    property alias gapsInRow: gapsInRow
    property alias gapsInScrub: gapsInScrub
    property alias gapsOutRow: gapsOutRow
    property alias gapsOutScrub: gapsOutScrub
    property alias roundRow: roundRow
    property alias roundScrub: roundScrub
    property alias roundPowRow: roundPowRow
    property alias roundPowScrub: roundPowScrub
    property alias borderRow: borderRow
    property alias borderScrub: borderScrub
    property alias resizeRow: resizeRow
    property alias layoutRow: layoutRow

    FieldRow {
        surface: look; id: gapsInRow
        label: "Gaps inner"; caption: "Space between tiled windows"; icon: "app-window"
        ScrubValue {
            id: gapsInScrub; s: look.s
            value: look.gapsIn; openValue: look.base.gapsIn
            from: winGrp.meta.gapsIn.min; to: winGrp.meta.gapsIn.max; step: winGrp.meta.gapsIn.step; unit: "px"
            onEdited: v => { look.gapsIn = v; look.writeDeco("gaps_in", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: gapsOutRow
        label: "Gaps outer"; caption: "Space to the screen edge"; icon: "monitor"
        ScrubValue {
            id: gapsOutScrub; s: look.s
            value: look.gapsOut; openValue: look.base.gapsOut
            from: winGrp.meta.gapsOut.min; to: winGrp.meta.gapsOut.max; step: winGrp.meta.gapsOut.step; unit: "px"
            onEdited: v => { look.gapsOut = v; look.writeDeco("gaps_out", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: roundRow
        label: "Rounding"; caption: "Corner radius in pixels"; icon: "record"
        ScrubValue {
            id: roundScrub; s: look.s
            value: look.rounding; openValue: look.base.rounding
            from: winGrp.meta.rounding.min; to: winGrp.meta.rounding.max; step: winGrp.meta.rounding.step; unit: "px"
            onEdited: v => { look.rounding = v; look.writeDeco("rounding", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: roundPowRow
        label: "Rounding power"; caption: "Higher bends corners to a squircle"; icon: "sparkles"
        ScrubValue {
            id: roundPowScrub; s: look.s
            value: look.roundingPower; openValue: look.base.roundingPower
            from: winGrp.meta.roundingPower.min; to: winGrp.meta.roundingPower.max; step: winGrp.meta.roundingPower.step
            onEdited: v => { look.roundingPower = v; look.writeDeco("rounding_power", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: borderRow
        label: "Border size"; caption: "Window outline thickness"; icon: "scaling"
        ScrubValue {
            id: borderScrub; s: look.s
            value: look.borderSize; openValue: look.base.borderSize
            from: winGrp.meta.borderSize.min; to: winGrp.meta.borderSize.max; step: winGrp.meta.borderSize.step; unit: "px"
            onEdited: v => { look.borderSize = v; look.writeDeco("border_size", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: resizeRow
        label: "Resize on border"; caption: "Drag a window edge to resize"; icon: "mouse"
        LinkToggle {
            s: look.s
            on: look.resizeOnBorder
            onToggled: {
                look.resizeOnBorder = !look.resizeOnBorder;
                look.writeDeco("resize_on_border", look.resizeOnBorder ? "true" : "false");
            }
        }
    }

    FieldRow {
        surface: look; id: layoutRow
        label: "Layout"; caption: "Window tiling layout"; icon: "mixer"
        SettingsSeg {
            s: look.s
            options: look.layoutOptions
            value: look.layout
            onPicked: v => { look.layout = v; look.writeDeco("layout", "\"" + v + "\""); }
        }
    }
}
