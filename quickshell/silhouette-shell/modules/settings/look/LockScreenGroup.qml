pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.settings
import qs.services
import qs.components.controls

/**
 * Lock-screen settings group: how the password beads land while typing (drop,
 * mobile, or pulse). Further lock-screen knobs land here as rows. Extracted
 * from the monolithic Look surface so the tab stays under 500 lines.
 */
Group {
    id: lockGrp

    property var look: null

    title: "Lock screen"
    s: look ? look.s : 1
    open: false

    property alias dotsRow: dotsRow

    FieldRow {
        surface: look; id: dotsRow
        label: "Dots animation"; caption: "Password beads style"; icon: "activity"
        SettingsSeg {
            s: look.s
            options: [
                { label: "Drop", value: "drop" },
                { label: "Mobile", value: "mobile" },
                { label: "Pulse", value: "pulse" }
            ]
            value: Flags.lockDotsMode
            onPicked: v => Flags.lockDotsMode = v
        }
    }
}
