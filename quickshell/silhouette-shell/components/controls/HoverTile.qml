pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Shared hover/focus backdrop for settings rows: the translucent fill that
 * lights while the pointer is over the row or the row holds keyboard focus,
 * with the same fast color glide every row used. Rows keep their own geometry
 * (anchors, radius, height) and their own HoverHandler for surface wiring —
 * this only owns the fill, its two input states and its motion.
 */
Rectangle {
    id: tile

    /** True while the owning row has keyboard focus (soul seam). */
    property bool focused: false
    /** True while the pointer is over the row. */
    property bool hovered: false
    /** Border color while hot; "transparent" (default) keeps the tile borderless. */
    property color edge: "transparent"

    color: (tile.hovered || tile.focused) ? Theme.frameBg : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    border.width: 1
    border.color: (tile.hovered || tile.focused) ? tile.edge : "transparent"
}
