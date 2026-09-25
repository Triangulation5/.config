pragma Singleton

import QtQuick

/**
 * Clock & Date: how the pill's clock reads, how the hover date strip settles,
 * how a timed calendar event announces itself, and where its weather glance looks
 * and how often it refreshes.
 */
QtObject {
    readonly property string name: "Clock & Date"
    readonly property string icon: "\u25D4"
    readonly property string keywords: "clock time date 12 24 hour seconds weather city glance refresh retry calendar strip idle return reminder alert chime alarm notify glyphs"

    readonly property var groups: [
        { card: "Clock", rows: [
            { key: "time12h", type: "toggle", label: "12-hour clock", caption: "AM/PM instead of 24-hour time", reset: true },
            { key: "clockSeconds", type: "toggle", label: "Show seconds", reset: false },
            { key: "showGlyphs", type: "toggle", label: "Japanese glyphs",
              caption: "Kanji headers and transport glyphs across the shell", reset: false }
        ]},
        { card: "Calendar", rows: [
            { key: "calendarIdleReturnMs", type: "slider", label: "Idle return",
              min: 500, max: 10000, step: 500, unit: "ms",
              caption: "How long the hover date strip waits before gliding back to today", reset: 2000 }
        ]},
        { card: "Reminders", rows: [
            { key: "eventChime", type: "toggle", label: "Reminder chime",
              caption: "Play the alarm chime when a timed calendar event starts", reset: true },
            { key: "eventNotify", type: "toggle", label: "Reminder notification",
              caption: "Post a desktop notification for the same event", reset: true }
        ]},
        { card: "Weather glance", rows: [
            { key: "weatherCity", type: "text", label: "City", placeholder: "WELLAND",
              caption: "wttr.in city for the calendar glance", reset: "WELLAND" },
            { key: "weatherRetryMs", type: "slider", label: "Retry gap",
              min: 5000, max: 120000, step: 5000, unit: "s", displayScale: 0.001,
              caption: "How often to retry locating while the city is still unknown", reset: 30000 },
            { key: "weatherRefreshMs", type: "slider", label: "Refresh",
              min: 300000, max: 7200000, step: 300000, unit: "min", displayScale: 0.0000166667,
              caption: "How often the forecast is refreshed once located", reset: 1200000 }
        ]}
    ]
}
