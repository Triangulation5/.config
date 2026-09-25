pragma ComponentBehavior: Bound

import QtQuick
import "../../../utils/settings/fields.js" as Fields
import qs.modules.settings
import qs.services
import qs.components.controls

/**
 * Night-light settings group: mode (off/on/scheduled), temperature, and
 * on/off schedule times. Extracted from the monolithic Look surface.
 */
Group {
    id: nightGrp

    property var look: null

    title: "Night light"
    s: look ? look.s : 1

    /**
     * This group's fields' bounds and steps, from the table shared with the
     * settings app's Control Center page (utils/settings/fields.js). A bound is a
     * property of the field, not of the control drawing it, so both read it here.
     */
    readonly property var meta: ({
        temp: Fields.get("flags", "nightLightTemp"),
        onMin: Fields.get("flags", "nightLightOnMin"),
        offMin: Fields.get("flags", "nightLightOffMin")
    })

    property alias nlModeRow: nlModeRow
    property alias nlTempRow: nlTempRow
    property alias nlTempScrub: nlTempScrub
    property alias nlOnRow: nlOnRow
    property alias nlOnScrub: nlOnScrub
    property alias nlOffRow: nlOffRow
    property alias nlOffScrub: nlOffScrub

    FieldRow {
        surface: look; id: nlModeRow
        label: "Mode"; caption: "Off, warm, or auto"; icon: "moon"
        SettingsSeg {
            s: look.s
            options: look.nightModeOptions
            value: Flags.nightLightMode
            onPicked: v => NightLight.setMode(v)
        }
    }

    FieldRow {
        surface: look; id: nlTempRow
        label: "Temperature"; caption: "Lower is warmer"; icon: "sun"
        collapsed: Flags.nightLightMode === "off"
        ScrubValue {
            id: nlTempScrub; s: look.s
            value: Flags.nightLightTemp; openValue: look.base.nlTemp
            from: nightGrp.meta.temp.min; to: nightGrp.meta.temp.max; step: nightGrp.meta.temp.step; unit: "K"
            onEdited: v => NightLight.setTemp(v)
        }
    }

    FieldRow {
        surface: look; id: nlOnRow
        label: "On at"; caption: "Warm tint starts"; icon: "clock"
        collapsed: Flags.nightLightMode !== "scheduled"
        ScrubValue {
            id: nlOnScrub; s: look.s
            value: Flags.nightLightOnMin; openValue: look.base.nlOnMin
            from: nightGrp.meta.onMin.min; to: nightGrp.meta.onMin.max; step: nightGrp.meta.onMin.step
            fmt: look.fmtClock
            onEdited: v => NightLight.setOnMin(v)
        }
    }

    FieldRow {
        surface: look; id: nlOffRow
        label: "Off at"; caption: "Back to neutral"; icon: "stopwatch"
        collapsed: Flags.nightLightMode !== "scheduled"
        ScrubValue {
            id: nlOffScrub; s: look.s
            value: Flags.nightLightOffMin; openValue: look.base.nlOffMin
            from: nightGrp.meta.offMin.min; to: nightGrp.meta.offMin.max; step: nightGrp.meta.offMin.step
            fmt: look.fmtClock
            onEdited: v => NightLight.setOffMin(v)
        }
    }
}
