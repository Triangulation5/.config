pragma Singleton

import QtQuick

/**
 * Control Center: night light, the session-wide keep-awake, and the rescan gaps
 * of the link panels' wifi and bluetooth drill-ins.
 *
 * The two schedule rows hold minutes since midnight and render as clock times;
 * the shell turns them into hyprsunset profiles, so the times here are the
 * ones the warm tint actually switches on and off at. The rescan rows are
 * stored in ms and shown in seconds.
 */
QtObject {
    readonly property string name: "Control Center"
    readonly property string icon: "\u2699"
    readonly property string keywords: "night light warmth sunset temperature schedule keep awake inhibit idle caffeine wifi bluetooth scan rescan network link"

    readonly property var groups: [
        { card: "Night light", rows: [
            { key: "nightLightMode", type: "segmented", label: "Mode",
              caption: "Warm the screen all day or on a schedule",
              options: ["off", "on", "scheduled"], names: ["Off", "On", "Scheduled"], reset: "scheduled" },
            { key: "nightLightTemp", type: "slider", label: "Temperature", min: 2500, max: 6500, step: 100,
              unit: "K", caption: "Lower is warmer", reset: 3600 },
            { key: "nightLightOnMin", type: "slider", label: "Warm at", min: 0, max: 1439, step: 15,
              format: "time", caption: "Warm tint starts", reset: 1200 },
            { key: "nightLightOffMin", type: "slider", label: "Neutral at", min: 0, max: 1439, step: 15,
              format: "time", caption: "Back to neutral", reset: 420 }
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
