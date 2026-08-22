pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * CameraEffects: the visual layer stacked over the live preview. Today it is a
 * bottom scrim (so the control capsules read over a bright feed) plus a faint
 * top sheen that echoes the pill body's own highlight. It is the seam where the
 * Dynamic Island effects land later — glass reflection, blur, the face-tracking
 * mesh, Face ID rings, the scan sweep and the unlock flash — without touching
 * CameraFeed or the controls.
 */
Item {
    id: root

    property real s: 1.1
    property bool enabled: true

    opacity: enabled ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    /** Bottom scrim so the control capsules stay legible over the feed. */
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 96 * root.s
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: "#66000000" }
        }
    }

    /** Faint top sheen, mirroring the pill body's highlight line. */
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.sheen
    }
}
