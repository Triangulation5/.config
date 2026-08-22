pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.components.icons

/**
 * CameraFeed: the live webcam feed, isolated from every layer above it. Owns
 * the QtMultimedia Camera + CaptureSession + VideoOutput, mirrors the frame
 * like a phone selfie cam when `mirrored`, and only runs while `active` (the
 * shared Camera service's active flag) so the device is released the moment the
 * island closes. A neutral placeholder stands in when no camera is present.
 *
 * This file imports neither the Camera service nor Face ID — it is pure
 * presentation of the feed, driven entirely by its own properties.
 */
Item {
    id: root

    property real s: 1.1
    property bool active: false
    property bool mirrored: true

    MediaDevices {
        id: mediaDevices
    }

    readonly property bool available: mediaDevices.videoInputs.length > 0

    Camera {
        id: camera
        active: root.active && root.available
    }

    CaptureSession {
        camera: camera
        videoOutput: videoOutput
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop

        transform: Scale {
            xScale: root.mirrored ? -1 : 1
            origin.x: videoOutput.width / 2
        }
    }

    /** Neutral no-camera placeholder (theme-agnostic by design). */
    Rectangle {
        anchors.fill: parent
        color: "#22222c"
        visible: !root.available

        GlyphIcon {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -12 * root.s
            width: 34 * root.s
            height: 34 * root.s
            name: "camera"
            color: "#606079"
            stroke: 1.6
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 10 * root.s
            text: "No camera"
            color: "#606079"
            font.family: "Inter"
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }
    }
}
