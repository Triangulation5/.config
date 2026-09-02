pragma ComponentBehavior: Bound

import QtQuick
import qs.components.animation
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
 * palette mode instead of breaking against it, and the fade's own opacity
 * rides the pill's surface opacity (Flags.pillOpacity, floor 0.75) so the
 * edge bands stay as translucent as the pill around them and never go too
 * weak to dissolve the label on a heavily translucent pill.
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
     * The fade bands' outer-edge color: the palette wash at the pill's own
     * surface opacity (Flags.pillOpacity is applied to the whole pill body
     * behind this text) so the bands blend the label into the surface without
     * leaving visible strips — but never drop below 0.75: on a heavily
     * translucent pill a 1:1 fade goes so weak the scrolling label ends up
     * with a hard, readable edge at the fade boundary instead of dissolving.
     */
    readonly property color edgeColor: Qt.rgba(
        root.fadeColor.r,
        root.fadeColor.g,
        root.fadeColor.b,
        Math.max(Flags.pillOpacity, 0.75)
    )

    EdgeFade {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        fadeWidth: root.fadeWidth
        fadeColor: root.edgeColor
        active: root.overflowing
    }

    EdgeFade {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        fadeWidth: root.fadeWidth
        fadeColor: root.edgeColor
        mirrored: true
        active: root.overflowing
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
