import QtQuick
import qs.components.controls

/**
 * The settings window's hover hint: one instance of the shell's own `Tooltip` —
 * the washi bubble the pill's chips, tray slots and the clipboard already wear —
 * shown for whichever row's caption is under the pointer.
 *
 * The captions used to be a second line under every option's label, which cost
 * a line of prose on every row of every page; they are the same text the rail
 * searches a row by, so they are worth keeping, just not worth printing. The
 * bubble is not per row: a page can hold forty-five options, and forty-five
 * tooltips is not a price a page should pay for one you might hover. One bubble
 * is enough, so this layer holds one — built the first time a captioned row is
 * hovered (`Hint.used`, which the content area's loader arms on) and reused for
 * every row after that.
 *
 * The bubble sits above the pointer and centres on it, so it reads as belonging
 * to the cursor rather than to the row it describes: a wide caption no longer
 * hangs off a middle the pointer is nowhere near. That is why the host is a
 * point and not the row's rect — `Tooltip` centres on its parent and hangs its
 * pointer off the parent's edge, so a zero-sized host standing on the cursor is
 * the whole of the placement.
 *
 * Two things the pill's tooltips never have to think about, because they float
 * over a pill wider than any of their labels: the bubble slides inward near the
 * layer's left and right edges until it fits, and it flips below the cursor on
 * the rows near the top, where there is no room above.
 */
Item {
    id: layer

    anchors.fill: parent

    /** The bubble stays at least this far inside the layer's edges. */
    readonly property int edge: 6

    /**
     * The pointer in this layer's coordinates. `Hint.pointer` is in scene
     * coordinates — the rows that report it know nothing of this layer — so it
     * is mapped here, and the bubble follows it as the pointer moves.
     */
    readonly property point here: layer.mapFromItem(null, Hint.pointer.x, Hint.pointer.y)

    /**
     * The room a bubble needs above the cursor. Sized off the bubble's own font
     * (`Tooltip.em` — 1.5em of padding, a line of text, the 0.5em pointer and
     * the 0.5em gap is four of them), and deliberately not off `tip.height`:
     * `Tooltip` re-anchors itself on `placement`, so measuring it from the
     * binding that sets `placement` is a binding loop.
     */
    readonly property real room: 4 * tip.em

    Item {
        id: host

        /**
         * The cursor's own point, slid horizontally so the bubble cannot leave
         * the layer. `Tooltip` centres itself on this item's centre, so on a
         * zero-width host at the cursor the bubble is centred on the cursor —
         * no offset arithmetic belongs here. The clamp bites only on a caption
         * wider than the room beside the cursor, and is expressed in the
         * bubble's own terms (`tip.width`) because the host stands on the
         * bubble's centre, not on its left edge.
         */
        x: Math.max(layer.edge + tip.width / 2,
                    Math.min(layer.here.x, layer.width - layer.edge - tip.width / 2))
        y: layer.here.y
        width: 0
        height: 0

        Tooltip {
            id: tip

            /** The caption itself; the row's label is already on screen beside it. */
            title: Hint.text
            show: Hint.hovering

            /** Above the cursor, or below it where the layer has no room above. */
            placement: layer.here.y > layer.edge + layer.room ? "above" : "below"
        }
    }
}
