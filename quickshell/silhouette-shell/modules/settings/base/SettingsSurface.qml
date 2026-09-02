pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.pill.surfaces
import qs.components.layout
import qs.components.animation

/**
 * Shared base for the morphing settings surfaces: the category index and each
 * sub-surface. Owns the surface header (kanji + label, back chevron or cog),
 * the content column that carries the page's rows, the keyboard-navigable row
 * registry and the glowing row-soul seam, and morphs back to the parent index
 * when empty space is clicked on a sub-surface. The deriving surface sets
 * `rows`, `kanji`/`label`, optionally `backSurface`, and declares its rows as
 * direct children (they land in the shared content column under the header).
 *
 * Each `rows` entry pairs a row item with its control kind and the backing getter
 * and setter: `seg` cycles a segmented choice (wrapping), `toggle` flips a
 * boolean, `scrub` bumps a numeric scrub through its `bump(dir)`, `nav` morphs
 * to another surface. The host routes arrow keys through `kbMove`,
 * `kbAdjust` and `kbActivate`; hover and clicks route through `reportRowHover`
 * and `activateRow`, keeping `kbIndex` and the seam in sync.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    property string backSurface: ""
    signal requestSurface(string name)

    property Item focusRowItem: null
    property int kbIndex: -1
    property var rows: []

    /** Header: kanji glyph + ALL-CAPS label; showBack or a cog icon on the right. */
    property string kanji: ""
    property string label: ""
    property bool showBack: true
    property string icon: ""

    /** Gap under the header before the first content child. */
    property real headerGap: 0

    /**
     * Extra content-column height past the content (sub-surfaces let the column
     * bleed into the bottom margin so nothing is cut at the last row).
     */
    property real contentExtra: 0
    /** Clip the content column to its rect (paired with contentExtra). */
    property bool contentClip: false

    /**
     * The page's rows, laid out under the shared header inside `body`, where
     * the cascade arms per-row stagger on creation.
     */
    default property alias content: body.data

    implicitHeight: contentCol.implicitHeight

    /**
     * Row reveal cascade: rows fade in one after another once the morph lands
     * (a touch quicker than the weather surface's bands — ~480 ms). Each row's
     * opacity and a small scale are bound to its index band of the shared
     * Cascade driver at creation; the header is not staggered.
     */
    Cascade {
        id: cascade
        morphCloseness: root.morphCloseness
        duration: 480
        count: 1
    }

    Component.onCompleted: root.armReveal()

    function rowReveal(i) {
        return cascade.item(i);
    }

    function armReveal() {
        var kids = body.children;
        cascade.count = kids.length;
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i];
            if (!k)
                continue;
            (function(idx) {
                k.opacity = Qt.binding(() => root.rowReveal(idx));
                k.scale = Qt.binding(() => 0.96 + 0.04 * root.rowReveal(idx));
            })(i);
        }
    }

    function reportRowHover(item, hovered) {
        if (hovered) {
            focusRowItem = item;
            kbIndex = rowIndexOf(item);
        }
    }
    onActiveChanged: if (!active) {
        focusRowItem = null;
        kbIndex = -1;
    }

    function rowIndexOf(item) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].item === item)
                return i;
        return -1;
    }

    /** Step a seg row's value by `dir`, wrapping at both ends like a mouse click. */
    function segCycle(r, dir) {
        var n = r.vals.length;
        var i = r.vals.indexOf(r.get());
        r.set(r.vals[(((i < 0 ? 0 : i) + dir) % n + n) % n]);
    }

    function kbMove(dir) {
        if (!rows.length)
            return;
        kbIndex = Math.max(0, Math.min(rows.length - 1, (kbIndex < 0 ? 0 : kbIndex + dir)));
        focusRowItem = rows[kbIndex].item;
    }

    function kbAdjust(dir) {
        if (!rows.length)
            return;
        if (kbIndex < 0) {
            kbIndex = 0;
            focusRowItem = rows[0].item;
        }
        var r = rows[kbIndex];
        if (r.kind === "seg")
            segCycle(r, dir);
        else if (r.kind === "toggle")
            r.set(dir > 0);
        else if (r.kind === "scrub")
            r.bump(dir);
    }

    function kbActivate() {
        if (kbIndex < 0)
            return;
        var r = rows[kbIndex];
        if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "nav")
            root.requestSurface(r.surface);
        else if (r.kind === "seg")
            segCycle(r, 1);
    }

    /**
     * A click anywhere on a row drives its control: toggles flip, nav rows open
     * their surface, and segmented rows step to the next value (wrapping). The
     * control's own hit areas stay on top, so clicking a specific segment still
     * picks it directly.
     */
    function activateRow(item) {
        var idx = rowIndexOf(item);
        if (idx < 0)
            return;
        kbIndex = idx;
        focusRowItem = item;
        var r = rows[idx];
        if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "nav")
            root.requestSurface(r.surface);
        else if (r.kind === "seg")
            segCycle(r, 1);
    }

    readonly property bool rowFocused: focusRowItem !== null && active

    ameForm: rowFocused ? "rowseam" : "off"
    amePoint: root.rowSeamPoint(root.focusRowItem)

    Column {
        id: contentCol
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        height: implicitHeight + root.contentExtra
        clip: root.contentClip

        SurfaceHeader {
            s: root.s
            kanji: root.kanji
            label: root.label
            showBack: root.showBack
            icon: root.icon
        }

        Item {
            width: 1
            height: root.headerGap
        }

        /**
         * Rows land here (default property alias above); armReveal staggers
         * them. A Column so its implicit height still measures the rows, like
         * when they were direct children of the page column.
         */
        Column {
            id: body
            width: parent.width
            spacing: 0
        }
    }
}
