pragma Singleton

import QtQuick
import "../utils/rows.js" as Rows

/**
 * Control Center: night light, the session-wide keep-awake, and the rescan gaps
 * of the link panels' wifi and bluetooth drill-ins.
 *
 * The two schedule rows hold minutes since midnight and render as clock times;
 * the shell turns them into hyprsunset profiles, so the times here are the
 * ones the warm tint actually switches on and off at. The rescan rows are
 * stored in ms and shown in seconds.
 *
 * The night-light bounds, step and default are not stated on the rows: they are
 * properties of the field, shared with the shell's own Night light group, and
 * live in one table (`utils/settings/fields.js` — read through `row()` below).
 * A row here carries only what this app alone decides: its editor type, label,
 * caption, unit, and any display tweak.
 */
QtObject {
    readonly property string name: "Control Center"
    readonly property string icon: "\u2699"
    readonly property string keywords: "night light warmth sunset temperature schedule keep awake inhibit idle caffeine wifi bluetooth scan rescan network link"

    /**
     * One row for the flag `field`, with its bounds, step, default and option
     * list taken from the shared table. `extra` carries what the table
     * deliberately does not — `unit`, `format` and the like are how a control
     * formats a value, not what the field accepts.
     */
    function row(field, type, label, caption, unit, extra) {
        return Rows.flag(field, type, label, caption, unit, extra);
    }

    readonly property var groups: [
        { card: "Night light", rows: [
            row("nightLightMode", "segmented", "Mode", "Warm the screen all day or on a schedule", ""),
            row("nightLightTemp", "slider", "Temperature", "Lower is warmer", "K"),
            row("nightLightOnMin", "slider", "Warm at", "Warm tint starts", "", { format: "time" }),
            row("nightLightOffMin", "slider", "Neutral at", "Back to neutral", "", { format: "time" })
        ]},
        { card: "Network", rows: [
            { key: "wifiScanMs", type: "slider", label: "Wi-Fi rescan",
              min: 5000, max: 60000, step: 5000, unit: "s", displayScale: 0.001,
              caption: "How often the Wi-Fi panel rescans for networks while it is open", reset: 10000 },
            { key: "btScanMs", type: "slider", label: "Bluetooth rescan",
              min: 5000, max: 60000, step: 5000, unit: "s", displayScale: 0.001,
              caption: "The same, for the Bluetooth panel", reset: 25000 }
        ]},
        { card: "Session", rows: [
            { key: "keepAwake", type: "toggle", label: "Keep awake",
              caption: "Inhibit idle until toggled off (also pauses the lock timeouts)", reset: false }
        ]}
    ]
}
