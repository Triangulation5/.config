pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import qs.components.layout

/**
 * One monitor's lock surface. Blurs a grab of the desktop behind a frozen sharp
 * overlay, then wipes the lock open by growing a pill-shaped mask from the pill's
 * resting spot to the full screen. Carries the glow field and, on the primary
 * monitor, the main Content.
 */

Item {
    id: surface
    property real s: 1.1
    property var auth: null
    property var pw: null
    property string screenName: ""

    /**
     * Drives the lock-open morph. A pill-shaped hole grows from the pill's resting
     * spot out to the full screen, wiping the lock open over the grabbed desktop.
     * The grow waits for the grab so it reveals onto the real desktop, the collapse
     * just runs on unlock.
     */
    property bool active: false
    property real maskP: 0

    readonly property bool overlayReady: deskOverlay.status === Image.Ready
    readonly property bool shouldOpen: active && overlayReady
    onShouldOpenChanged: if (shouldOpen)
        openAnim.restart()
    onActiveChanged: if (!active)
        closeAnim.restart()

    /**
     * The lock UI's primary screen is just the first one Quickshell reports, so
     * the auth panel lands on one deterministic monitor without pinning a display
     * name that only exists on Erik's machine.
     */
    readonly property bool isMain: {
        var scr = Quickshell.screens;
        if (scr.length === 0)
            return true;
        return surface.screenName === scr[0].name;
    }

    readonly property real spread: 2.4
    readonly property size half: Qt.size(Math.max(2, Math.round(width / 2)), Math.max(2, Math.round(height / 2)))
    readonly property size quarter: Qt.size(Math.max(2, Math.round(width / 4)), Math.max(2, Math.round(height / 4)))
    readonly property size eighth: Qt.size(Math.max(2, Math.round(width / 8)), Math.max(2, Math.round(height / 8)))
    readonly property vector2d eighthVec: Qt.vector2d(eighth.width, eighth.height)

    readonly property string shotSource: {
        if (surface.screenName.length === 0)
            return "";
        var dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";
        return "file://" + dir + "/ricelin-lock-" + surface.screenName + ".png";
    }

    clip: true

    /**
     * The blurred desktop backdrop. It is the whole build cost, so it loads a beat
     * after the surface mounts; the cheap sharp overlay and clock are up first,
     * which keeps the compositor from showing a black gap while this instantiates.
     * The hole reveals this once the pill grows.
     */
    Loader {
        id: blurLayer
        anchors.fill: parent
        active: true
        asynchronous: true

        sourceComponent: Component {
          Item {
            anchors.fill: parent

            Image {
                id: bgImg
                anchors.fill: parent
                source: surface.shotSource
                fillMode: Image.PreserveAspectCrop
                smooth: true
                cache: false
                asynchronous: true
                visible: false
            }

            ShaderEffectSource {
                id: downHalf
                anchors.fill: parent
                sourceItem: bgImg
                textureSize: surface.half
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: copyHalf
                anchors.fill: parent
                visible: false
                property var source: downHalf
            }

            ShaderEffectSource {
                id: downQuarter
                anchors.fill: parent
                sourceItem: copyHalf
                textureSize: surface.quarter
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: copyQuarter
                anchors.fill: parent
                visible: false
                property var source: downQuarter
            }

            ShaderEffectSource {
                id: downEighth
                anchors.fill: parent
                sourceItem: copyQuarter
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: blurH1
                anchors.fill: parent
                visible: false
                property var source: downEighth
                property vector2d resolution: surface.eighthVec
                property vector2d blurDir: Qt.vector2d(1, 0)
                property real spread: surface.spread
                fragmentShader: "../../assets/shaders/blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurH1Src
                anchors.fill: parent
                sourceItem: blurH1
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: blurV1
                anchors.fill: parent
                visible: false
                property var source: blurH1Src
                property vector2d resolution: surface.eighthVec
                property vector2d blurDir: Qt.vector2d(0, 1)
                property real spread: surface.spread
                fragmentShader: "../../assets/shaders/blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurV1Src
                anchors.fill: parent
                sourceItem: blurV1
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: blurH2
                anchors.fill: parent
                visible: false
                property var source: blurV1Src
                property vector2d resolution: surface.eighthVec
                property vector2d blurDir: Qt.vector2d(1, 0)
                property real spread: surface.spread
                fragmentShader: "../../assets/shaders/blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurH2Src
                anchors.fill: parent
                sourceItem: blurH2
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: blurV2
                anchors.fill: parent
                visible: false
                property var source: blurH2Src
                property vector2d resolution: surface.eighthVec
                property vector2d blurDir: Qt.vector2d(0, 1)
                property real spread: surface.spread
                fragmentShader: "../../assets/shaders/blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurV2Src
                anchors.fill: parent
                sourceItem: blurV2
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: blurH3
                anchors.fill: parent
                visible: false
                property var source: blurV2Src
                property vector2d resolution: surface.eighthVec
                property vector2d blurDir: Qt.vector2d(1, 0)
                property real spread: surface.spread
                fragmentShader: "../../assets/shaders/blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurH3Src
                anchors.fill: parent
                sourceItem: blurH3
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                id: blurV3
                anchors.fill: parent
                visible: false
                property var source: blurH3Src
                property vector2d resolution: surface.eighthVec
                property vector2d blurDir: Qt.vector2d(0, 1)
                property real spread: surface.spread
                fragmentShader: "../../assets/shaders/blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurV3Src
                anchors.fill: parent
                sourceItem: blurV3
                textureSize: surface.eighth
                smooth: true
                hideSource: true
                visible: false
            }

            ShaderEffect {
                anchors.fill: parent
                property var source: blurV3Src
                property vector2d srcSize: surface.eighthVec
                property real darken: 0.62
                fragmentShader: "../../assets/shaders/grade.frag.qsb"
            }
          }
        }
    }

    GlowField {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.55
    }

    Content {
        anchors.fill: parent

        s: surface.s
        auth: surface.auth
        pw: surface.pw
        isMain: surface.isMain

        enabled: surface.maskP >= 1
    }

    /**
     * The frozen desktop grab, sharp and opaque, punched with a pill-shaped hole.
     * As the hole grows the lock wipes open; outside the hole you keep seeing your
     * own desktop, never black. Loaded synchronously so it is ready the frame the
     * lock mounts and the reveal never opens onto a blank.
     */
    Image {
        id: deskOverlay
        anchors.fill: parent
        source: surface.shotSource
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        asynchronous: false
        visible: false
        layer.enabled: true
    }

    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            id: pillMask

            color: "white"
            antialiasing: true

            readonly property real pillW: 176 * surface.s
            readonly property real pillH: 42 * surface.s
            readonly property real pillY: (Flags.notchStyle ? 0 : 8 * Flags.topGap) * surface.s

            readonly property real gameFlat: Flags.gameMode ? 1 : 0

            width: Flags.gameMode ? surface.width : pillW + (surface.width - pillW) * surface.maskP
            height: pillH + (surface.height - pillH) * surface.maskP

            x: Flags.gameMode ? 0 : (surface.width - width) / 2
            y: Flags.gameMode ? pillY : pillY * (1 - surface.maskP)

            topLeftRadius: Flags.notchStyle ? 0 : (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
            topRightRadius: Flags.notchStyle ? 0 : (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
            bottomLeftRadius: (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
            bottomRightRadius: (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
        }

        /** Left notch ear. */
        RoundCorner {
            visible: Flags.notchStyle

            anchors.right: pillMask.left
            anchors.top: pillMask.top
            anchors.rightMargin: -1

            size: pillMask.height / 2
            corner: RoundCorner.CornerEnum.TopRight

            color: "white"

            /**
             * Keep the ear visible through most of the opening animation,
             * then let it fade out as the pill finishes expanding.
             */
            opacity: surface.maskP < 0.8 ? 1 : (1 - surface.maskP) / 0.2

            /**
             * Slightly enlarge the ear as the pill grows to better sell
             * the liquid morph without changing the mask geometry.
             */
            scale: 1 + surface.maskP * 0.15

            antialiasing: true
            Behavior on opacity {
                NumberAnimation {
                    duration: 60
                }
            }
        }

        /** Right notch ear. */
        RoundCorner {
            visible: Flags.notchStyle

            anchors.left: pillMask.right
            anchors.top: pillMask.top
            anchors.leftMargin: -1

            size: pillMask.height / 2
            corner: RoundCorner.CornerEnum.TopLeft

            color: "white"

            /** Match the left ear's timing. */
            opacity: surface.maskP < 0.8 ? 1 : (1 - surface.maskP) / 0.2

            /** Match the left ear's subtle growth. */
            scale: 1 + surface.maskP * 0.15

            antialiasing: true
            Behavior on opacity {
                NumberAnimation {
                    duration: 60
                }
            }
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: deskOverlay
        maskEnabled: true
        maskInverted: true
        maskSource: maskItem
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    /**
     * The open eases in and out so it grows on smoothly instead of popping, the
     * close keeps the liquid pillMorph curve that already feels right.
     */
    NumberAnimation {
        id: openAnim
        target: surface
        property: "maskP"
        to: 1
        duration: 620
        easing.type: Easing.InOutCubic
    }

    NumberAnimation {
        id: closeAnim
        target: surface
        property: "maskP"
        to: 0
        duration: 560
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }
}
