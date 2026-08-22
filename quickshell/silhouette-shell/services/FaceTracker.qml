pragma Singleton

import QtQuick
import Quickshell

/**
 * FaceTracker: placeholder for the future face-detection backend. Today it is
 * an inert interface so the Face ID visual layer and the unlock pipeline have a
 * stable thing to bind to. The future implementation will push frames from
 * services/Camera through OpenCV (or a PipeWire face track) and expose the live
 * detect state plus the face's bounding box, which FaceIdUnlock animates against
 * and Auth eventually consumes for PAM unlock.
 */
Singleton {
    id: root

    /** True while detection is actively processing frames. */
    property bool active: false

    /** True when a face is currently in frame. */
    property bool detected: false

    /** Normalized face bounds (0..1) within the camera feed. */
    property rect faceRect: Qt.rect(0, 0, 0, 0)

    function start() { root.active = true; }
    function stop() { root.active = false; root.reset(); }
    function reset() { root.detected = false; root.faceRect = Qt.rect(0, 0, 0, 0); }
}
