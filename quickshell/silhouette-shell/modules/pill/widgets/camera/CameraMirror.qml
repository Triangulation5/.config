pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.pill.surfaces
import qs.modules.pill.widgets.camera

/**
 * CameraMirror: the camera island surface. A rounded, clipped live feed
 * (CameraFeed) is the base layer; the glass/effects layer (CameraEffects), the
 * Face ID overlay (FaceIdUnlock) and the control capsules (CameraControls)
 * stack above it, so the island is a visual platform for the Dynamic Island
 * features rather than a bare webcam viewer.
 *
 * The shared Camera service owns the device state: the island acquires it
 * while open and releases it on close, and mirrors on request. The pill only
 * knows this surface by name — never the camera implementation, face detection
 * or authentication.
 */
PillSurface {
    id: root

    mTop: 0
    mLeft: 0
    mRight: 0
    mBottom: 0

    /** Compact island vs full controls view (sizes the pill via implicit size). */
    property bool expanded: true

    property bool effectsOn: true

    implicitWidth: (expanded ? 360 : 220) * root.s
    implicitHeight: (expanded ? 460 : 160) * root.s

    /** Ame stays off: nothing for the bead to dock on over a live feed. */
    ameForm: "off"

    onActiveChanged: {
        if (active)
            Camera.start();
        else
            Camera.stop();
    }

    /** Rounded, clipped viewport matching the pill's open corner radius. */
    Rectangle {
        id: viewport
        anchors.fill: parent
        radius: 22 * root.s
        clip: true
        color: "#0b0b10"

        CameraFeed {
            anchors.fill: parent
            active: Camera.active
            mirrored: Camera.mirrored
            s: root.s
        }

        CameraEffects {
            anchors.fill: parent
            enabled: root.effectsOn
            s: root.s
        }

        FaceIdUnlock {
            anchors.fill: parent
            s: root.s
        }

        CameraControls {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.expanded
            mirrored: Camera.mirrored
            effectsOn: root.effectsOn
            s: root.s
            onMirrorRequested: Camera.mirrored = !Camera.mirrored
            onEffectsRequested: root.effectsOn = !root.effectsOn
            onSettingsRequested: { /* future: camera settings */ }
        }
    }
}
