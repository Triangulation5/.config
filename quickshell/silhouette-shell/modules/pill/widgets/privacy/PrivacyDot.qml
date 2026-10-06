pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * The privacy indicator: a dot that is there only when it has something to say.
 *
 * Three states, and the third is the one that matters. `idle` draws nothing at
 * all — not a grey dot, which would train the eye to ignore it. `capture` is a
 * filled vermilion. `unknown` is an amber ring, drawn because the check could
 * not be run, and it is deliberately *louder* than the quiet state rather than
 * quieter: an indicator that fails to a blank is the one failure mode that
 * makes this worse than having no indicator at all.
 *
 * The capture state breathes. A static red dot on a top edge is easy to stop
 * seeing, and this one has to be noticed at a glance from across a desk; a slow
 * pulse carries without being loud. The pulse is `Motion.heat` — the slowest
 * step in the ladder — and it collapses to nothing under `reduceMotion`, which
 * multiplies every duration in the shell at once (see `services/Motion.qml`).
 *
 * Two sizes, one component. `compact` is a bare dot for the rest pill, which is
 * 38px tall and has room for exactly that. `full` adds the application name
 * for the hover face, where there is space and where rule 2 of the brief
 * actually gets paid off: "something is using your microphone" is much weaker
 * than "Firefox is using your microphone".
 *
 * Everything it draws comes from `Theme`, so it follows the colourscheme
 * automatically. The two tones are fixed across schemes on purpose — see the
 * note on `privacyCapture` in `services/ColorScheme.qml`.
 */
Item {
    id: root

    /** Uniform scale from the pill, as every other widget takes. */
    property real s: 1

    /** `compact` is a dot alone; `full` adds the label. */
    property string variant: "compact"

    /** Layout scale for the two variants. The rest pill takes a bare dot. */
    readonly property real scaleFactor: variant === "full" ? 1 : 0.62

    /**
     * The width reserved for the label in `full`, fixed rather than measured.
     *
     * The hover face sizes the pill from `statusRow`'s implicitWidth, and that
     * row re-measures the clock's flight origin whenever its width changes
     * (`onImplicitWidthChanged` in HoverFace.qml). The label is measured, not
     * reserved, a capture would shove the clock sideways every time a
     * microphone opened — and shove it back when it closed. The slot is
     * constant and the label elides inside it, exactly as the download chip
     * keeps a constant footprint in the same row.
     */
    readonly property real labelSlot: 150 * s

    implicitWidth: variant === "full" ? dot.width + 8 * s + labelSlot : dot.width
    implicitHeight: Math.max(dot.height, label.implicitHeight)

    /**
     * True when the service has something to say. False is the idle state,
     * which draws nothing at all.
     *
     * This is deliberately *not* the item's own `visible`. A Row skips its
     * invisible children when measuring itself — checked, not assumed: a Row
     * of 50px and 30px children reports implicitWidth 50 with the second
     * hidden and 90 with it shown — so hiding this item would change
     * `hoverRow`'s implicitWidth on every capture start and stop, and
     * `refreshClockStart` would re-measure the clock's flight origin under the
     * user's finger. The item stays visible and holds its footprint; only what
     * it draws comes and goes.
     */
    readonly property bool active: Privacy.visible

    /** True while something is capturing. */
    readonly property bool capturing: Privacy.capturing

    /** True when the capture check could not be run. */
    readonly property bool unknown: Privacy.unknown

    /**
     * The line under the dot in `full`. `Privacy.label` already names the
     * capturing application and distinguishes a still-running capture from an
     * unanswerable check, so this does not have to re-derive any of it.
     */
    Text {
        id: label
        visible: root.variant === "full" && root.active
        anchors.left: dot.right
        anchors.leftMargin: 8 * root.s
        anchors.verticalCenter: dot.verticalCenter
        text: Privacy.label
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: Math.round(11 * root.s)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        width: root.labelSlot
        /** A brief lift so a newly started capture is noticed, not just seen. */
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    Item {
        id: dot
        anchors.verticalCenter: parent.verticalCenter
        width: 10 * root.s * root.scaleFactor
        height: width

        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        /**
         * The breath. Driven by a number rather than a state so it can ease
         * rather than snap, and so a change of state never restarts it into a
         * visible jump — the dot fades between tones instead.
         */
        SequentialAnimation on pulse {
            running: root.capturing && !root.unknown
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: Motion.heat; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: Motion.heat; easing.type: Easing.InOutSine }
            onStopped: pulse = 0
        }
        property real pulse: 0

        /**
         * Capture: a filled dot with a halo that breathes. Unknown: a ring
         * rather than a fill, because "we cannot tell" is not the same claim as
         * "something is recording" and should not look like it.
         */
        Rectangle {
            id: halo
            anchors.centerIn: parent
            width: parent.width * (2.1 + dot.pulse * 0.9)
            height: width
            radius: width / 2
            color: root.unknown ? Theme.privacyUnknown : Theme.privacyCapture
            opacity: root.unknown ? 0.28 : 0.10 + dot.pulse * 0.22
            visible: opacity > 0.01
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        }

        Rectangle {
            id: core
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: root.unknown ? "transparent" : Theme.privacyCapture
            border.width: root.unknown ? Math.max(1.5, 1.6 * root.s) : 0
            border.color: Theme.privacyUnknown
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            Behavior on border.color { ColorAnimation { duration: Motion.standard } }
        }
    }
}
