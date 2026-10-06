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
 * This is a mark and nothing else: no label, no variant, no size switch. The
 * rest surface is 38px tall and holds a dot, which is all a badge that size
 * should carry. A fuller version with the application name was tried on the
 * hover face and taken back out — the hover row is sized by what is in it, and
 * reserving room for a name indented the pill on every hover for a dot that is
 * idle almost always.
 *
 * Everything it draws comes from `Theme`, so it follows the colourscheme
 * automatically. The two tones are fixed across schemes on purpose — see the
 * note on `privacyCapture` in `services/ColorScheme.qml`.
 */
Item {
    id: root

    /** Uniform scale from the pill, as every other widget takes. */
    property real s: 1

    implicitWidth: dot.width
    implicitHeight: dot.height

    /**
     * True when the service has something to say. False is the idle state,
     * which draws nothing at all.
     */
    readonly property bool active: Privacy.visible

    /**
     * Hidden when idle. On the rest surface this changes no layout — the dot is
     * anchored to the pill's right edge — but it keeps an idle dot out of any
     * measurement it might later be dragged into.
     */
    visible: active

    /** True while something is capturing. */
    readonly property bool capturing: Privacy.capturing

    /** True when the capture check could not be run. */
    readonly property bool unknown: Privacy.unknown

    Item {
        id: dot
        anchors.verticalCenter: parent.verticalCenter

        /** A 10px mark at 62%: at full size it crowds the 38px rest pill. */
        width: 6.2 * root.s
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