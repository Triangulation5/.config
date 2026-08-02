pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property real mult: Flags.reduceMotion ? 0.4 : 1

    /**
     * Liquid physical motion is enabled automatically for notch style:
     * - slight overshoot
     * - heavier settle
     * - more organic pill movement
     *
     * Standard motion is preserved for the normal pill style.
     */
    readonly property bool liquidMotion: Flags.notchStyle

    readonly property int fast:     Math.round(140 * mult)
    readonly property int standard: Math.round(300 * mult)
    readonly property int morph:    Math.round((liquidMotion ? 700 : 420) * mult)
    readonly property int shapeshift: Math.round((liquidMotion ? 950 : 820) * mult)
    readonly property int glide:    Math.round((liquidMotion ? 360 : 260) * mult)
    readonly property int heat:     Math.round(1100 * mult)

    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeMorph:    Easing.BezierSpline

    /**
     * Liquid morph curve, cubic-bezier(0.16, 1, 0.3, 1). Front-loaded like an
     * exponential chase but with a long, visible settle tail. Use with
     * easeMorph (BezierSpline).
     *
     * When notchStyle is enabled:
     * - slight overshoot
     * - controlled settle
     *
     * When notchStyle is disabled:
     * - original curve is preserved.
     */
    readonly property var morphCurve: liquidMotion ? [
        0.22, 1.28,
        0.36, 1,
        1, 1
    ] : [
        0.16, 1,
        0.3, 1,
        1, 1
    ]

    readonly property real rSmall: 7
    readonly property real rTile:  13

    /** Looping scan/pairing breath pulse. */
    readonly property int pulse: Math.round((liquidMotion ? 650 : 420) * mult)
}
