pragma ComponentBehavior: Bound

import QtQuick
import ".."
import qs.services
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
            from: 1; to: 20; step: 1; unit: "px"
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
            from: 1; to: 5; step: 1
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
            from: 0; to: 1; step: 0.01; decimals: 2
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
            from: 0; to: 0.2; step: 0.01; decimals: 2
            onEdited: v => { look.blurNoise = v; look.writeBlur("noise", v.toFixed(2)); }
        }
    }
}
