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

    /**
     * Material uses the M3 state layer (on-surface at 8–10 %) with no outline;
     * Washi keeps the original frame wash and editable edge.
     */
    color: (tile.hovered || tile.focused)
        ? (Theme.material
            ? (tile.focused ? Theme.stateFocus : Theme.stateHover)
            : (tile.focused ? Qt.alpha(Theme.cream, 0.08) : Theme.frameBg))
        : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    border.width: Theme.material ? 0 : 1
    border.color: (tile.hovered || tile.focused) ? tile.edge : "transparent"
}
