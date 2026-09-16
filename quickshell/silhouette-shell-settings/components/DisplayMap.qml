import QtQuick
import qs.config
import qs.components

/**
 * The arrangement peek: every output drawn to scale in the position Hyprland has
 * it, inside one bounding box — a desk panel left of a laptop comes out left of
 * the laptop here, and a monitor stacked above another sits above it.
 *
 * The rectangles are the outputs' logical ones (the mode over the scale), which
 * is the space the compositor itself lays windows out in, so the map cannot
 * disagree with where a window actually lands. Each screen is drawn exactly on
 * its own rectangle — the shape's stand hangs below it instead of taking room from
 * it — because a map whose screens were all a little smaller than their
 * rectangles would show gaps between monitors that sit flush against each other.
 * `chrome` is the room that hangs off the bottom and is reserved once for the
 * whole box, not per tile.
 *
 * The fit is capped in height as well as width, because two 16:9 screens in a
 * vertical stack are twice as tall as they are wide and would otherwise run off
 * the card.
 *
 * Each tile is a DisplayShape, sized down: the map is the same portrait the
 * monitor's card shows, so a glance at the map and a glance at the card describe
 * the same screen. This item only reports — selecting an output and scrolling to
 * its settings is the page's decision.
 */
Item {
    id: root

    /** Live monitors, as `hyprctl` reports them. */
    property var mons: []

    /** The output the config declares main, marked with a dot. */
    property string mainName: ""

    /** The output the page is showing. */
    property string selName: ""

    /** How tall the arrangement may get, stands included, before it is scaled down. */
    property real maxHeight: 132

    /** The room a stand needs below the bottom row: DisplayShape's tallest. */
    readonly property real chrome: 11

    signal picked(string name)

    /**
     * Fitted tile rects and the height they need, rebuilt whenever a monitor's
     * mode, scale or position changes. Anchored at the layout's own origin, so a
     * config whose monitors start at a negative x (one placed left of the main
     * output) still fills the box.
     */
    readonly property var layout: {
        var mons = root.mons;
        if (!mons || mons.length === 0 || root.width <= 0)
            return { h: 0, tiles: [] };

        var rects = [];
        var minX = Infinity;
        var minY = Infinity;
        var maxX = -Infinity;
        var maxY = -Infinity;

        for (var i = 0; i < mons.length; i++) {
            var m = mons[i];
            var w = Math.round(m.width / Math.max(0.1, m.scale));
            var h = Math.round(m.height / Math.max(0.1, m.scale));
            rects.push({ mon: m, name: m.name, x: m.x, y: m.y, w: w, h: h });
            minX = Math.min(minX, m.x);
            minY = Math.min(minY, m.y);
            maxX = Math.max(maxX, m.x + w);
            maxY = Math.max(maxY, m.y + h);
        }

        var spanX = Math.max(1, maxX - minX);
        var spanY = Math.max(1, maxY - minY);
        var k = Math.min(root.width / spanX, Math.max(1, root.maxHeight - root.chrome) / spanY);
        var ox = (root.width - spanX * k) / 2;

        var tiles = [];
        for (var j = 0; j < rects.length; j++) {
            var r = rects[j];
            tiles.push({
                mon: r.mon, name: r.name, below: false,
                x: ox + (r.x - minX) * k,
                y: (r.y - minY) * k,
                w: r.w * k, h: r.h * k
            });
        }

        // A stand under a screen that has another screen under it would be
        // painted across the neighbour, so those tiles drop theirs. The test is
        // overlap in x plus a tile that starts at this one's bottom edge.
        for (var a = 0; a < tiles.length; a++)
            for (var b = 0; b < tiles.length; b++) {
                if (a === b)
                    continue;
                if (tiles[b].x + tiles[b].w > tiles[a].x + 1 && tiles[a].x + tiles[a].w > tiles[b].x + 1
                    && tiles[b].y >= tiles[a].y + tiles[a].h - 1) {
                    tiles[a].below = true;
                    break;
                }
            }

        return { h: spanY * k + root.chrome, tiles: tiles };
    }

    implicitHeight: root.layout.h

    Repeater {
        model: root.layout.tiles

        delegate: DisplayShape {
            id: tile

            required property var modelData

            // A tile only labels itself when there is room for the text inside the
            // screen it draws: at six monitors wide the names would be a smear.
            readonly property bool roomy: tile.modelData.w > 74 && tile.modelData.h > 32

            // Placed by its screen's top-left corner, not by the middle of the
            // item: the screen inside the item is the tile rect, and only the
            // stand hangs past it.
            x: tile.modelData.x
            y: tile.modelData.y
            width: tile.implicitWidth
            height: tile.implicitHeight
            mon: tile.modelData.mon
            main: tile.modelData.name === root.mainName
            sel: tile.modelData.name === root.selName
            hovered: tileArea.containsMouse
            stand: !tile.modelData.below
            labels: tile.roomy
            labelSize: Math.max(8, Math.min(11, tile.modelData.h / 7))
            maxWidth: tile.modelData.w
            maxHeight: tile.modelData.h + root.chrome

            MouseArea {
                id: tileArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(tile.modelData.name)
            }
        }
    }
}
