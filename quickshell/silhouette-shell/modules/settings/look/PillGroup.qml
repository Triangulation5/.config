pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.settings
import qs.services
import qs.modules.controlcenter
import qs.components.controls

/**
 * Pill settings group: top gap, app gap, opacity, blur toggle, vim keys,
 * and notch flare. Extracted from the monolithic Look surface.
 */
Group {
    id: pillGrp

    property var look: null

    title: "Pill"
    s: look ? look.s : 1
    open: true

    property alias pillGapRow: pillGapRow
    property alias pillGapScrub: pillGapScrub
    property alias appGapRow: appGapRow
    property alias appGapScrub: appGapScrub
    property alias pillOpRow: pillOpRow
    property alias pillOpScrub: pillOpScrub
    property alias pillBlurRow: pillBlurRow
    property alias vimKeysRow: vimKeysRow
    property alias notchFlareRow: notchFlareRow
    property alias notchFlareScrub: notchFlareScrub

    FieldRow {
        surface: look; id: pillGapRow
        label: "Pill gap"; caption: "Space above pill. Lower moves it up."; icon: "chevron-up"
        ScrubValue {
            id: pillGapScrub; s: look.s
            value: Flags.topGap; openValue: look.base.topGap
            from: -1; to: 2; step: 0.1; decimals: 1
            onEdited: v => Flags.topGap = v
        }
    }

    FieldRow {
        surface: look; id: appGapRow
        label: "App gap"; caption: "Space under pill. Lower moves view up."; icon: "chevron-down"
        ScrubValue {
            id: appGapScrub; s: look.s
            value: Flags.appGap; openValue: look.base.appGap
            from: 0; to: 2; step: 0.1; decimals: 1
            onEdited: v => Flags.appGap = v
        }
    }

    FieldRow {
        surface: look; id: pillOpRow
        label: "Pill opacity"; caption: "How see-through the pill sits"; icon: "sun"
        ScrubValue {
            id: pillOpScrub; s: look.s
            value: Flags.pillOpacity; openValue: look.base.pillOpacity
            from: 0.55; to: 1.0; step: 0.05; decimals: 2
            onEdited: v => Flags.pillOpacity = v
        }
    }

    FieldRow {
        surface: look; id: pillBlurRow
        label: "Pill blur"; caption: "Frosts pill. Needs opacity under 100%."; icon: "sparkles"
        LinkToggle {
            s: look.s
            on: Flags.pillBlur
            onToggled: {
                Flags.pillBlur = !Flags.pillBlur;
                look.applyPillBlur(Flags.pillBlur);
            }
        }
    }

    FieldRow {
        surface: look; id: vimKeysRow
        label: "Vim keys"; caption: "hjkl navigation. Disables arrow keys."; icon: "keyboard"
        LinkToggle {
            s: look.s
            on: Flags.vimKeys
            onToggled: Flags.vimKeys = !Flags.vimKeys
        }
    }

    FieldRow {
        surface: look; id: notchFlareRow
        label: "Notch flare"; caption: "Flare of both notch ears."; icon: "bolt"
        collapsed: !Flags.notchStyle
        ScrubValue {
            id: notchFlareScrub; s: look.s
            value: Flags.notchFlare; openValue: look.base.notchFlare
            from: -7; to: 10; step: 0.25; decimals: 2; unit: "px"
            onEdited: v => Flags.notchFlare = v
        }
    }
}
