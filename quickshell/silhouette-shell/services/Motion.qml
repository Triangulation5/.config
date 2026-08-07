pragma Singleton
import QtQuick
import Quickshell
import qs.services

/**
 * Shared motion language. One singleton owns the animation durations, easing
 * types, and the morph bezier curve every surface morph rides, all scaled by the
 * reduce-motion flag; notch style swaps in a quicker, Apple-inspired profile.
 */

Singleton {
    readonly property real mult: Flags.reduceMotion ? 0.45 : 1

    /**
     * Liquid physical motion is enabled automatically for notch style.
     *
     * The default pill preserves the original timing profile, while the notch
     * adopts a more Apple-inspired motion with quicker response and a subtle,
     * controlled settle.
     */
    readonly property bool liquidMotion: Flags.notchStyle
    readonly property int fast:        Math.round((liquidMotion ? 160 : 140) * mult)
    readonly property int standard:    Math.round((liquidMotion ? 260 : 300) * mult)
    readonly property int morph:       Math.round((liquidMotion ? 520 : 420) * mult)
    readonly property int shapeshift:  Math.round((liquidMotion ? 700 : 820) * mult)
    readonly property int glide:       Math.round((liquidMotion ? 300 : 260) * mult)
    readonly property int heat:        Math.round((liquidMotion ? 900 : 1100) * mult)
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeMorph:    Easing.BezierSpline

    /**
     * Morph curve used with easeMorph (BezierSpline).
     *
     * Default:
     *   Original cubic-bezier(0.16, 1, 0.3, 1) curve.
     *
     * Notch:
     *   A slightly more front-loaded Apple-style curve with a very subtle
     *   overshoot, giving the pill a lighter, more fluid feel without becoming
     *   overly elastic.
     */
    readonly property var morphCurve: liquidMotion ? [
        0.20, 1.18,
        0.36, 1,
        1,    1
    ] : [
        0.16, 1,
        0.30, 1,
        1,    1
    ]

    readonly property real rSmall: 7
    readonly property real rTile:  13

    /** Looping scan/pairing breath pulse. */
    readonly property int pulse: Math.round((liquidMotion ? 800 : 420) * mult)
}
