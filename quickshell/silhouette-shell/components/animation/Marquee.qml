pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services

/**
 * Single-line text that ping-pong scrolls when wider than the available width,
 * so long track and artist names stay readable. Caller sets the width (e.g.
 * via anchors) and `active` to gate the motion. The label snaps to whole pixels
 * so NativeRendering stays crisp while it scrolls.
 *
 * While the text overflows, a palette-colored fade dissolves both edges so the
 * scrolling label sinks into the card instead of clipping hard. The fade color
 * derives from the theme palette (cardTop/cardBot), so it tracks dynamic
 * palette mode instead of breaking against it.
 */
Item {
    id: root

    property string text: ""
    property color color: Theme.cream
    property real pixelSize: 14
    property int weight: Font.Normal
    property bool active: true

    /** Width of the palette fade at each edge; 0 disables the fade. */
    property real fadeWidth: 18
    /** Palette color the edge fades dissolve into. */
    property color fadeColor: root.washColor

    property real scrollX: 0

    implicitHeight: label.implicitHeight
    clip: true

    readonly property bool overflowing: label.implicitWidth > width

    /**
     * Blend of the surface palette colors, weighted slightly toward cardTop to
     * match the card's vertical wash where the text rows sit. Derived from the
     * theme rather than hardcoded so it follows dynamic palette mode.
     */
    readonly property color washColor: Theme.mix(Theme.cardTop, Theme.cardBot, 0.35)

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(root.scrollX)
        text: root.text
        color: root.color
        renderType: Text.NativeRendering
        font.family: Theme.font
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        elide: root.overflowing ? Text.ElideNone : Text.ElideRight
        width: root.overflowing ? implicitWidth : root.width

        onTextChanged: root.sync()
    }

    /**
     * One edge's palette fade: a horizontal LinearGradient shape from
     * transparent to the palette color. The right edge reuses this shape
     * mirrored with scale: -1, so the fade direction flips with it.
     */
    component EdgeFade: Shape {
        width: root.fadeWidth
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: root.overflowing && root.fadeWidth > 0

        ShapePath {
            startX: 0
            startY: 0
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: root.fadeWidth
                y2: 0
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: root.fadeColor }
            }
            PathLine { x: root.fadeWidth; y: 0 }
            PathLine { x: root.fadeWidth; y: height }
            PathLine { x: 0; y: height }
            PathLine { x: 0; y: 0 }
        }
    }

    EdgeFade {
        anchors.left: parent.left
    }

    EdgeFade {
        anchors.right: parent.right
        scale: -1
    }

    SequentialAnimation {
        id: anim
        loops: Animation.Infinite
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "scrollX"
            from: 0
            to: -(label.implicitWidth - root.width)
            duration: Math.max(1, label.implicitWidth - root.width) * 22
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "scrollX"
            from: -(label.implicitWidth - root.width)
            to: 0
            duration: Math.max(1, label.implicitWidth - root.width) * 22
            easing.type: Easing.InOutSine
        }
    }

    onActiveChanged: sync()
    onOverflowingChanged: sync()
    Component.onCompleted: sync()

    /**
     * Fully imperative start/stop: a `running` binding here would be severed
     * by the first imperative stop() and leave the loop animating forever
     * inside a hidden surface. Re-syncing on overflow changes also refreshes
     * the captured from/to endpoints after a width change.
     */
    function sync() {
        anim.stop();
        root.scrollX = 0;
        if (overflowing && active)
            anim.start();
    }
}
