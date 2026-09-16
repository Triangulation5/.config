pragma Singleton

import QtQuick

/**
 * Timers: how long the shell waits. The pill's lazy-loading pair (how long a
 * closed surface is kept alive, and how often the sweep looks for one to evict),
 * the hover grace before the pill collapses, how long an overlay stays up, and
 * how long a notification popup lives.
 *
 * The surface idle timeout used to sit on the Pill shape page among forty-eight
 * sizes. It is a duration, not a shape, and it is the one setting here that a
 * person is likely to reach for ("the pill keeps swallowing my Escape") — so it
 * moved to where the other timeouts are. Nothing else about it changed: same
 * flag, same default, same search result.
 */
QtObject {
    readonly property string name: "Timers"
    readonly property string icon: "\u25F4"
    readonly property string caption: "How long the shell waits"
    readonly property string keywords: "timers timeout timeouts duration durations wait delay grace sweep hold popup idle lazy eviction expires surface"

    readonly property var groups: [
        { card: "Pill", rows: [
            { key: "pillSurfaceIdleTimeout", type: "slider", label: "Surface idle timeout",
              min: 0, max: 60, step: 1, unit: "s",
              caption: "Close an open surface left untouched this long (0 = keep it)", reset: 12 },
            { key: "pillCleanupSec", type: "slider", label: "Cleanup sweep",
              min: 2, max: 60, step: 1, unit: "s",
              caption: "How often the pill looks for closed surfaces to evict", reset: 10 },
            { key: "pillHoverGraceMs", type: "slider", label: "Hover grace",
              min: 0, max: 1000, step: 50, unit: "ms",
              caption: "How long the pill waits before collapsing after the pointer leaves", reset: 300 }
        ]},
        { card: "Overlays", rows: [
            { key: "osdHoldMs", type: "slider", label: "Overlay hold",
              min: 500, max: 5000, step: 100, unit: "ms",
              caption: "How long a volume, brightness or track overlay stays up", reset: 1800 }
        ]},
        { card: "Notifications", rows: [
            { key: "notifMs", type: "slider", label: "Popup time",
              min: 1000, max: 20000, step: 500, unit: "ms",
              caption: "How long a notification popup stays on screen", reset: 6000 },
            { key: "notifLowMs", type: "slider", label: "Low urgency",
              min: 1000, max: 20000, step: 500, unit: "ms",
              caption: "The same, for a notification that marks itself low", reset: 4000 }
        ]}
    ]
}
