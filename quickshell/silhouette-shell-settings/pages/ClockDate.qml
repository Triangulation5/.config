pragma Singleton

import QtQuick

/**
 * Clock & Date: how the pill's clock reads and where its weather glance looks.
 */
QtObject {
    readonly property string name: "Clock & Date"
    readonly property string icon: "\u25D4"

    readonly property var groups: [
        { card: "Clock", rows: [
            { key: "time12h", type: "toggle", label: "12-hour clock", caption: "AM/PM instead of 24-hour time", reset: true },
            { key: "clockSeconds", type: "toggle", label: "Show seconds", reset: false },
            { key: "showGlyphs", type: "toggle", label: "Japanese glyphs",
              caption: "Kanji headers and transport glyphs across the shell", reset: false }
        ]},
        { card: "Weather glance", rows: [
            { key: "weatherCity", type: "text", label: "City", placeholder: "WELLAND",
              caption: "wttr.in city for the calendar glance", reset: "WELLAND" }
        ]}
    ]
}
