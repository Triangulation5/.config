pragma ComponentBehavior: Bound

import QtQuick
import ".."
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
            from: 2200; to: 6000; step: 100; unit: "K"
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
            from: 0; to: 1425; step: 15
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
            from: 0; to: 1425; step: 15
            fmt: look.fmtClock
            onEdited: v => NightLight.setOffMin(v)
        }
    }
}
