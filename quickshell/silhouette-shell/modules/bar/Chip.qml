import QtQuick
import qs.services

/**
 * A status readout's chip: the block sits centred on a padded, rounded backdrop,
 * so a strip block can carry a fill of its own.
 *
 * With `Flags.barChips` off the chip lays the block out exactly as if it were not
 * there — the padding closes to zero and the fill goes transparent — so the
 * strip's rhythm is the same with chips on and off, and no block has to know.
 *
 * `fill` and `edge` are plain properties rather than a fixed pair so a readout can
 * pass a tone of its own, and passing a `fill` is on its own enough to bring the
 * chip up: that is how one block that is worth shouting about gets a backdrop
 * while the rest of the strip stays bare.
 *
 * No MouseArea: the bar is a glance, not a control surface.
 */
Rectangle {
    id: root

    property real s: 1

    /** Tone overrides; the palette's chip pair when left null. */
    property var fill: null
    property var edge: null

    /** A fill of its own is an explicit ask, so it counts as on. */
    readonly property bool on: BarStyle.chips || root.fill !== null
    readonly property real padX: on ? 7 * s : 0
    readonly property real padY: on ? 2 * s : 0

    implicitWidth: content.implicitWidth + 2 * root.padX
    implicitHeight: content.implicitHeight + 2 * root.padY
    radius: 4 * s
    color: on ? (root.fill !== null ? root.fill : BarStyle.chipFill) : "transparent"
    border.width: on ? 1 : 0
    border.color: root.edge !== null ? root.edge : BarStyle.chipEdge

    /** The block itself, declared inside as if the chip were not there. */
    default property alias block: content.data

    /**
     * Sizing host for the block. The block keeps its own geometry at 0,0 and this
     * takes its extent, which is then centred in the Rectangle — one level of
     * indirection so the block's sizing never has to know the chip's.
     */
    Item {
        id: content
        anchors.centerIn: parent
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
