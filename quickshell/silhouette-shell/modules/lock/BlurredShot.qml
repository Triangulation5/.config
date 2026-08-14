pragma ComponentBehavior: Bound

import QtQuick

/**
 * The blurred desktop backdrop for the lock reveal. Takes the frozen screenshot
 * and runs it through the same down-sample -> 3x separable blur -> grade chain
 * the lock surface carried inline, so the pill-shaped hole reveals a soft, dark
 * version of the desktop behind. Loaded asynchronously by the lock surface so
 * the cheap sharp overlay and clock are up first, which keeps the compositor
 * from showing a black gap while this instantiates.
 */
Item {
    id: root

    property url source: ""

    /** Blur reach, in lock-surface scale units. */
    property real spread: 2.4

    /** How much the final grade darkens the result. */
    property real darken: 0.62

    readonly property size half: Qt.size(Math.max(2, Math.round(width / 2)), Math.max(2, Math.round(height / 2)))
    readonly property size quarter: Qt.size(Math.max(2, Math.round(width / 4)), Math.max(2, Math.round(height / 4)))
    readonly property size eighth: Qt.size(Math.max(2, Math.round(width / 8)), Math.max(2, Math.round(height / 8)))
    readonly property vector2d eighthVec: Qt.vector2d(eighth.width, eighth.height)

    Image {
        id: bgImg
        anchors.fill: parent
        source: root.source
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
        textureSize: root.half
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
        textureSize: root.quarter
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
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: blurH1
        anchors.fill: parent
        visible: false
        property var source: downEighth
        property vector2d resolution: root.eighthVec
        property vector2d blurDir: Qt.vector2d(1, 0)
        property real spread: root.spread
        fragmentShader: "../../assets/shaders/blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurH1Src
        anchors.fill: parent
        sourceItem: blurH1
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: blurV1
        anchors.fill: parent
        visible: false
        property var source: blurH1Src
        property vector2d resolution: root.eighthVec
        property vector2d blurDir: Qt.vector2d(0, 1)
        property real spread: root.spread
        fragmentShader: "../../assets/shaders/blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurV1Src
        anchors.fill: parent
        sourceItem: blurV1
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: blurH2
        anchors.fill: parent
        visible: false
        property var source: blurV1Src
        property vector2d resolution: root.eighthVec
        property vector2d blurDir: Qt.vector2d(1, 0)
        property real spread: root.spread
        fragmentShader: "../../assets/shaders/blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurH2Src
        anchors.fill: parent
        sourceItem: blurH2
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: blurV2
        anchors.fill: parent
        visible: false
        property var source: blurH2Src
        property vector2d resolution: root.eighthVec
        property vector2d blurDir: Qt.vector2d(0, 1)
        property real spread: root.spread
        fragmentShader: "../../assets/shaders/blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurV2Src
        anchors.fill: parent
        sourceItem: blurV2
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: blurH3
        anchors.fill: parent
        visible: false
        property var source: blurV2Src
        property vector2d resolution: root.eighthVec
        property vector2d blurDir: Qt.vector2d(1, 0)
        property real spread: root.spread
        fragmentShader: "../../assets/shaders/blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurH3Src
        anchors.fill: parent
        sourceItem: blurH3
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: blurV3
        anchors.fill: parent
        visible: false
        property var source: blurH3Src
        property vector2d resolution: root.eighthVec
        property vector2d blurDir: Qt.vector2d(0, 1)
        property real spread: root.spread
        fragmentShader: "../../assets/shaders/blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurV3Src
        anchors.fill: parent
        sourceItem: blurV3
        textureSize: root.eighth
        smooth: true
        hideSource: true
        visible: false
    }

    ShaderEffect {
        anchors.fill: parent
        property var source: blurV3Src
        property vector2d srcSize: root.eighthVec
        property real darken: root.darken
        fragmentShader: "../../assets/shaders/grade.frag.qsb"
    }
}
