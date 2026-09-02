pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * One edge's horizontal dissolve: a LinearGradient band that runs the surface
 * color at the outer (clip) edge down to transparent toward the content, so
 * overflowing text sinks into its surface instead of clipping hard. This is
 * the reusable form of the fades the marquee lays over its scrolling label;
 * any clipped, centered content can ride the same treatment (the lock's
 * password capsule fades its dots and revealed text this way).
 *
 * Anchor the band to one side of the clipped content (top/bottom for its
 * height, plus left or right for its placement) and give it the surface's
 * exact color and alpha as `fadeColor` so the band is invisible over empty
 * surface and only appears where content passes beneath it. Set `mirrored`
 * for the right edge: the gradient's own axis is flipped (x1/x2 swap), so
 * the stop order and geometry stay untouched and the band is the exact
 * mirror of the left one - opaque at the outer (clip) edge, transparent
 * toward the content - with no shape transforms involved. `active` gates
 * the band entirely - keep it off while the content fits, so it never shows.
 */
Shape {
    id: root

    /** Flip the gradient axis so the opaque edge lands on the right. */
    property bool mirrored: false
    /** Width of the dissolve band from the clip edge inward. */
    property real fadeWidth: 18
    /** Outer-edge color, at the alpha of the surface the content sits on. */
    property color fadeColor: "transparent"
    /** Master switch: off while the content fits so the band never shows. */
    property bool active: true

    width: fadeWidth
    visible: active && fadeWidth > 0

    ShapePath {
        startX: 0
        startY: 0
        /** No stroke: the ShapePath's default black pen would box the fade in. */
        strokeColor: "transparent"
        fillGradient: LinearGradient {
            /**
             * The gradient always runs opaque (position 0) at the band's
             * outer edge and transparent (position 1) inward. For the right
             * band the outer edge is the local +x side, so the axis flips
             * via x1/x2 - never the stops, never a transform.
             */
            x1: root.mirrored ? root.fadeWidth : 0
            y1: 0
            x2: root.mirrored ? 0 : root.fadeWidth
            y2: 0
            GradientStop { position: 0.0; color: root.fadeColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
        PathLine { x: root.fadeWidth; y: 0 }
        PathLine { x: root.fadeWidth; y: height }
        PathLine { x: 0; y: height }
        PathLine { x: 0; y: 0 }
    }
}