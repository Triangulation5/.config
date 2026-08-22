pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell

/**
 * Camera: backend state for the camera/mirror system. Owns device availability,
 * whether the feed should be running, and the selfie mirror flag — plus the
 * exposure slot the future backend will drive. No UI lives here; the camera
 * visual module (CameraMirror/CameraFeed) reads and mutates this singleton.
 *
 * `active` is reference-counted so several monitors can hold the feed open and
 * the device only stops when the last holder lets go. Future integrations —
 * PipeWire camera access, permission handling, OpenCV face detection and the
 * Face ID unlock pipeline — all hang off this service rather than the widgets.
 */
Singleton {
    id: root

    /** True when at least one video input is present. */
    readonly property bool available: mediaDevices.videoInputs.length > 0

    /** True while the feed should be running. */
    property bool active: false

    /** Selfie mirror; flips the preview horizontally. */
    property bool mirrored: true

    /** Future exposure control, driven by the camera backend. */
    property real exposure: 0

    property int _holders: 0

    /** Acquire the camera; call from each surface that wants the feed. */
    function start() {
        root._holders = root._holders + 1;
        root.active = root._holders > 0;
    }

    /** Release the camera; the device stops once the last holder lets go. */
    function stop() {
        root._holders = Math.max(0, root._holders - 1);
        root.active = root._holders > 0;
    }

    MediaDevices {
        id: mediaDevices
    }
}
