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
 * `Tooltip` anchors itself to its parent and centres on it, so the bubble hangs
 * off `host`: an item wearing the hovered row's rect. Moving the host moves the
 * bubble, which is how the nudge below keeps a wide caption from hanging out
 * over the rail — the one thing the pill's tooltips never have to think about,
 * since they float over a pill that is wider than any of their labels.
 */
Item {
    id: layer

    anchors.fill: parent

    /** The bubble stays at least this far inside the layer's edges. */
    readonly property int edge: 6

    /** The row the bubble belongs to; null while the pointer is elsewhere. */
    readonly property Item row: Hint.anchor

    /** The row's rect in this layer's coordinates, following the page's scroll. */
    readonly property rect rowRect: {
        if (layer.row === null)
            return Qt.rect(0, 0, 0, 0);
        const p = layer.row.mapToItem(layer, 0, 0);
        return Qt.rect(p.x, p.y, layer.row.width, layer.row.height);
    }

    /**
     * The last rect the pointer was over, latched rather than bound: the bubble
     * fades out over a beat *after* the pointer has gone, and by then `row` is
     * already null — without this it would fade out in the layer's top-left
     * corner instead of where the row it describes is.
     */
    property rect shown: Qt.rect(0, 0, 0, 0)
    onRowRectChanged: if (layer.row !== null) layer.shown = layer.rowRect

    Item {
        id: host

        /**
         * The row's rect, slid horizontally so the bubble (which centres itself
         * on this item) cannot leave the layer. The nudge only bites on a
         * caption wider than the column it describes, and leaves the host on the
         * row's own rect otherwise.
         */
        x: Math.max(layer.edge + tip.width / 2,
                    Math.min(layer.shown.x + layer.shown.width / 2,
                             layer.width - layer.edge - tip.width / 2))
           - layer.shown.width / 2
        y: layer.shown.y
        width: layer.shown.width
        height: layer.shown.height

        Tooltip {
            id: tip

            /** The caption itself; the row's label is already on screen beside it. */
            title: Hint.text
            show: Hint.hovering

            /**
             * Above the row, or below it on the rows near the top of the page,
             * where there is no room in the layer for a bubble of this height.
             */
            placement: layer.shown.y > tip.height + layer.edge ? "above" : "below"
        }
    }
}
