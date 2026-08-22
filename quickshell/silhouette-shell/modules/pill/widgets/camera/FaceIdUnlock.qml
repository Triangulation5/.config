pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * FaceIdUnlock: the Face ID overlay that sits above the camera feed. It is a
 * small state machine over six phases — idle, cameraActive, searching, detected,
 * scanning and success — driving the glyph's tint/breath and the orbit ring's
 * grow/collapse. It knows nothing about the camera or authentication: the
 * future FaceTracker service will set `phase`, and Auth will consume the
 * success transition. For now it is drivable manually so the animation can be
 * eyeballed before the backend lands.
 */
Item {
    id: root

    property real s: 1.1

    /**
     * One of: "idle", "cameraActive", "searching", "detected", "scanning", "success".
     */
    property string phase: "idle"

    readonly property bool searching: phase === "searching"
    readonly property bool detected: phase === "detected"
    readonly property bool scanning: phase === "scanning"
    readonly property bool success: phase === "success"

    readonly property bool warm: detected || scanning || success
    readonly property color glyphColor: warm ? Theme.flameGlow : Theme.cream
    readonly property real orbitRadius: scanning ? 62 * root.s : 0

    FaceIdGlyph {
        anchors.centerIn: parent
        width: 96 * root.s
        height: 96 * root.s
        breathing: root.searching
        color: root.glyphColor
        s: root.s
    }

    FaceIdOrbit {
        anchors.centerIn: parent
        radius: root.orbitRadius
        color: root.glyphColor
        s: root.s
    }
}
