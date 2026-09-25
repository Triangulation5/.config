pragma ComponentBehavior: Bound

import QtQuick
import "../../../utils/settings/fields.js" as Fields
import qs.modules.settings
import qs.modules.controlcenter
import qs.components.controls

/**
 * Blur settings group: enable toggle, strength, passes, vibrancy, and noise.
 * Extracted from the monolithic Look surface.
 */
Group {
    id: blurGrp

    property var look: null

    title: "Blur"
    s: look ? look.s : 1

    /**
     * This group's fields' bounds and steps, from the table shared with the
     * settings app's Look page (utils/settings/fields.js) — see WindowGroup.
     */
    readonly property var meta: ({
        blurSize: Fields.get("deco", "blurSize"),
        blurPasses: Fields.get("deco", "blurPasses"),
        blurVibrancy: Fields.get("deco", "blurVibrancy"),
        blurNoise: Fields.get("deco", "blurNoise")
    })

    property alias blEnRow: blEnRow
    property alias blSizeRow: blSizeRow
    property alias blSizeScrub: blSizeScrub
    property alias blPassRow: blPassRow
    property alias blPassScrub: blPassScrub
    property alias blVibRow: blVibRow
    property alias blVibScrub: blVibScrub
    property alias blNoiseRow: blNoiseRow
    property alias blNoiseScrub: blNoiseScrub

    FieldRow {
        surface: look; id: blEnRow
        label: "Enabled"; caption: "Blur behind transparent windows"; icon: "droplet"
        LinkToggle {
            s: look.s
            on: look.blurOn
            onToggled: {
                look.blurOn = !look.blurOn;
                look.writeBlur("enabled", look.blurOn ? "true" : "false");
            }
        }
    }

    FieldRow {
        surface: look; id: blSizeRow
        label: "Strength"; caption: "Blur radius"; icon: "waves"
        collapsed: !look.blurOn
        ScrubValue {
            id: blSizeScrub; s: look.s
            value: look.blurSize; openValue: look.base.blurSize
            from: blurGrp.meta.blurSize.min; to: blurGrp.meta.blurSize.max; step: blurGrp.meta.blurSize.step; unit: "px"
            onEdited: v => { look.blurSize = v; look.writeBlur("size", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: blPassRow
        label: "Passes"; caption: "More passes, smoother blur"; icon: "reboot"
        collapsed: !look.blurOn
        ScrubValue {
            id: blPassScrub; s: look.s
            value: look.blurPasses; openValue: look.base.blurPasses
            from: blurGrp.meta.blurPasses.min; to: blurGrp.meta.blurPasses.max; step: blurGrp.meta.blurPasses.step
            onEdited: v => { look.blurPasses = v; look.writeBlur("passes", String(v)); }
        }
    }

    FieldRow {
        surface: look; id: blVibRow
        label: "Vibrancy"; caption: "Color saturation behind the blur"; icon: "palette"
        collapsed: !look.blurOn
        ScrubValue {
            id: blVibScrub; s: look.s
            value: look.blurVibrancy; openValue: look.base.blurVibrancy
            from: blurGrp.meta.blurVibrancy.min; to: blurGrp.meta.blurVibrancy.max; step: blurGrp.meta.blurVibrancy.step; decimals: 2
            onEdited: v => { look.blurVibrancy = v; look.writeBlur("vibrancy", v.toFixed(2)); }
        }
    }

    FieldRow {
        surface: look; id: blNoiseRow
        label: "Noise"; caption: "Grain mixed into the blur"; icon: "cloud-fog"
        collapsed: !look.blurOn
        ScrubValue {
            id: blNoiseScrub; s: look.s
            value: look.blurNoise; openValue: look.base.blurNoise
            from: blurGrp.meta.blurNoise.min; to: blurGrp.meta.blurNoise.max; step: blurGrp.meta.blurNoise.step; decimals: 2
            onEdited: v => { look.blurNoise = v; look.writeBlur("noise", v.toFixed(2)); }
        }
    }
}
