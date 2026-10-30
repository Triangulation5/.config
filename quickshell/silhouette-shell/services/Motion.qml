pragma Singleton
import QtQuick
import Quickshell
import qs.services

/**
 * Shared motion language. One singleton owns the animation durations, easing
 * types, and the morph bezier curve every surface morph rides, all scaled by the
 * reduce-motion flag; notch style swaps in a quicker, Apple-inspired profile,
 * and the design language supplies the base ladder (Washi is the original
 * timing, Material is Google's more expressive settle).
 *
 * It is also the single place the shell's animation speed can be turned: every
 * duration below is `something * mult`, so the settings app's speed flag scales
 * the whole shell from here instead of from thirty call sites.
 */

Singleton {
    readonly property real mult: (Flags.reduceMotion ? 0.45 : 1) * Math.max(0.1, Flags.motionSpeed)

    /**
     * Liquid physical motion is enabled automatically for notch style.
     *
     * The default pill preserves the original timing profile, while the notch
     * adopts a more Apple-inspired motion with quicker response and a subtle,
     * controlled settle.
     */
    readonly property bool liquidMotion: Flags.notchStyle
    readonly property int fast:        Math.round((liquidMotion ? 160 : Style.motionFast) * mult)
    readonly property int standard:    Math.round((liquidMotion ? 260 : Style.motionStandard) * mult)
    readonly property int morph:       Math.round((liquidMotion ? 520 : Style.motionMorph) * mult)
    readonly property int shapeshift:  Math.round((liquidMotion ? 700 : Style.motionShapeshift) * mult)
    readonly property int glide:       Math.round((liquidMotion ? 300 : Style.motionGlide) * mult)
    readonly property int heat:        Math.round((liquidMotion ? 900 : Style.motionHeat) * mult)
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
        0.20, 1.22,
        0.36, 1,
        1,    1
    ] : Style.motionCurve

    readonly property real rSmall: Style.radiusSmall
    readonly property real rTile:  Style.radiusTile

    /** Looping scan/pairing breath pulse. */
    readonly property int pulse: Math.round((liquidMotion ? 800 : Style.motionPulse) * mult)
}
