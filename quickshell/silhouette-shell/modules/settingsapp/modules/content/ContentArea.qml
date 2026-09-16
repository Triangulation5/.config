import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.settingsapp.config
import qs.modules.settingsapp.pages
import qs.modules.settingsapp.components

/**
 * The content column: the page header, the open page's body and the floating
 * reset button — composition only. A page renders either its data `groups`
 * through SettingGroup (which dispatches each row to its editor) or, when it
 * declares a `view`, a component of its own for a body whose rows cannot be
 * written as data (Displays: one card per monitor). Nothing here knows what a
 * setting looks like.
 *
 * `pageIndex` is normally bound to the rail's selection by the host, so nothing
 * in this file may assign to it: an assignment would destroy the host's binding
 * and silently disconnect the rail. The chevrons ask the host to move instead,
 * through `onNavigate`, exactly as the rows write through Sources rather than
 * assigning to their own value. Without a handler (a standalone preview) this
 * component moves itself.
 *
 * `targetKey` is the other half of a search: the rail's hit sets it to the row
 * it found, and this scrolls that row into view and lets the card ring it. The
 * reveal is retried rather than done once, because the row belongs to a delegate
 * that is built *because* the page just changed — the first frames after a
 * switch have no such item to measure — and because `builtRows` may not have
 * reached it yet.
 *
 * Pages are built lazily in two senses. What is not open does not exist: a card
 * is only created for the open page (the rail's own model is data, not items),
 * and a page's body component is only loaded when that page is shown. And what
 * is being opened is built a frame's worth at a time rather than all at once:
 * see `rowBuilder`. Building the whole page in one go is what used to make a
 * switch snap — 17 rows measured 55ms on this machine, about three dropped
 * frames — while nothing here is built ahead of being looked at.
 *
 * The other half of that is `groupOffsets`: what a card is handed has to describe
 * the page that is open *now*, or the card can be handed a row count of zero and
 * sit empty. It is derived from `pageGroups` rather than recorded when the page
 * changes, which is what keeps the two in step — see the property itself.
 */
Item {
    id: root

    property int pageIndex: 0

    /** The flag key or config field of the row to show, or "" for no target. */
    property string targetKey: ""

    /**
     * The open page's cards, or none when the page renders a body of its own
     * (`view`). The array itself is the rail's data, so it costs nothing to
     * hold; the items per card are what `builtRows` gates.
     */
    readonly property var pageGroups: (root.pageView === null && root.page) ? root.page.groups : []

    /** Every row of the open page, flattened — what the builder walks. */
    readonly property var pageRows: (root.pageView === null && root.page) ? Pages.pageRows(root.page) : []

    /**
     * First row of each card within the open page, for `visibleRows` below.
     *
     * Derived, not recorded. This was once a plain property written when the page
     * changed, which left it a page behind: the page-change handler reads
     * `pageGroups` before the binding that fills it has re-evaluated, so the
     * offsets it recorded were the *outgoing* page's. A card whose index was past
     * the end of that shorter array read `undefined`, `Math.max` made the sum NaN,
     * and the `int` truncated it to 0 — the card came up empty until you left the
     * page and came back. Read as a binding it is computed from `pageGroups` in the
     * same pass that fills it, so it cannot lag the page it describes.
     */
    readonly property var groupOffsets: {
        var out = [];
        var start = 0;
        var groups = root.pageGroups;
        for (var i = 0; i < groups.length; i++) {
            out.push(start);
            start += groups[i].rows.length;
        }
        return out;
    }

    /** How many of the open page's rows exist so far. See rowBuilder. */
    property int builtRows: 0

    /** Reveal attempts left before the timer gives up on a key that is not here. */
    property int revealTries: 0

    /**
     * Optional host handler called with the step to take (-1 back, +1 forward).
     * The host owns the page index, so it moves itself and this item's
     * `pageIndex` binding follows.
     */
    property var onNavigate: null

    readonly property var page: Pages.pages[pageIndex]
    readonly property string pageTitle: root.page ? root.page.name : ""
    /** The page's one-liner for the header. Empty if it declares none. */
    readonly property string pageCaption: (root.page && root.page.caption) ? root.page.caption : ""
    /** The page's own body component, when it has one instead of groups. */
    readonly property var pageView: root.page && root.page.view ? root.page.view : null

    function go(step) {
        var next = root.pageIndex + step;
        if (next < 0 || next >= Pages.pages.length)
            return;
        if (root.onNavigate !== null)
            root.onNavigate(step);
        else
            root.pageIndex = next;
    }

    /**
     * Scroll the target row into view. Returns false while the page's delegates
     * are not there yet — the page may be mid-build — which is what makes the
     * retry timer worth having.
     */
    function revealRow() {
        for (var g = 0; g < groupRepeater.count; g++) {
            var group = groupRepeater.itemAt(g);
            var slot = group ? group.itemFor(root.targetKey) : null;
            if (!slot)
                continue;
            var flick = scroll.contentItem;
            var y = slot.mapToItem(contentColumn, 0, 0).y;
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - 24));
            return true;
        }
        return false;
    }

    onTargetKeyChanged: if (root.targetKey.length > 0) root.scheduleReveal()
    onPageIndexChanged: {
        root.startPage();
        if (root.targetKey.length > 0)
            root.scheduleReveal();
    }

    Component.onCompleted: root.startPage()

    /**
     * Empty the content area so the builder can fill the page that is opening.
     *
     * A page that is not open holds no rows, which is the lazy half of this file.
     * The offsets need no handling here: they follow `pageGroups` on their own
     * (see `groupOffsets`), so this only has to drop the count to zero.
     */
    function startPage() {
        root.builtRows = 0;
    }

    function scheduleReveal() {
        root.revealTries = 0;
        revealTimer.restart();
    }

    /** Restore every row on the open page to its shipped default. */
    function resetCurrentPage() {
        var rows = Pages.pageRows(root.page);
        for (var i = 0; i < rows.length; i++)
            if (rows[i].reset !== undefined)
                Sources.write(rows[i], rows[i].reset);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 20

        PageNav {
            title: root.pageTitle
            caption: root.pageCaption
            index: root.pageIndex
            count: Pages.pages.length
            onStep: function(dir) { root.go(dir) }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // Same reason as the rail: the default bar is a foreign grey slab laid
            // over the cards. Scrolling is the wheel and the trackpad here.
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: contentColumn
                // The scroll view's viewport is inset by the layout's own
                // margins on both sides.
                width: root.width - 56
                spacing: 22

                Repeater {
                    id: groupRepeater
                    model: root.pageGroups

                    delegate: SettingGroup {
                        required property var modelData
                        required property int index
                        group: modelData
                        targetKey: root.targetKey

                        /**
                         * How many of this card's rows have been built. Both
                         * reads are properties rather than calls, so both are
                         * tracked: the card follows the builder, and follows the
                         * page when it changes. A card left over from the page
                         * that just left has no offset here and shows nothing.
                         */
                        visibleRows: {
                            var start = root.groupOffsets[index];
                            if (start === undefined)
                                return 0;
                            return Math.max(0, Math.min(modelData.rows.length, root.builtRows - start));
                        }
                    }
                }

                /**
                 * A page whose body is a component of its own (Displays: one
                 * card per monitor). Loaded when the page is shown and dropped
                 * when it is left, and loaded asynchronously so the component
                 * is compiled off the UI thread rather than during the switch.
                 */
                Loader {
                    Layout.fillWidth: true
                    visible: root.pageView !== null
                    source: root.pageView !== null ? root.pageView : ""
                    asynchronous: true
                }

                // What a source had to say about the last write ("Hyprland
                // reload failed", "added it to input.lua"), so a refused write
                // is never silent.
                Text {
                    Layout.fillWidth: true
                    visible: Sources.note.length > 0
                    text: Sources.note
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSection
                    wrapMode: Text.WordWrap
                }

                // Breathing room so the floating reset button never sits on top
                // of the last card while scrolled to the bottom.
                Item { Layout.preferredHeight: 56 }
            }
        }
    }

    /**
     * The builder. A page's rows are added a frame's worth at a time instead of
     * in one pass: each pass adds rows until its budget has gone, so cheap rows
     * land together (most pages are done in two or three frames) and an expensive
     * one cannot blow the frame budget on its own.
     *
     * The budget is the larger half of a frame at 60Hz, and a pass runs about
     * once per frame, so the frame the builder is in stays inside the budget. It
     * used to be 6ms, which left the biggest page (Pill shape, 47 rows) still
     * filling after a quarter of a second — long enough to read as a page that
     * never finished. Nothing is built for a page that is not open, and the pass
     * stops on its own once the page is full.
     */
    Timer {
        id: rowBuilder
        interval: 1
        repeat: true
        running: root.builtRows < root.pageRows.length
        onTriggered: {
            var deadline = Date.now() + 9;
            while (root.builtRows < root.pageRows.length && Date.now() < deadline)
                root.builtRows += 1;
        }
    }

    /**
     * A page switch lands the delegates over a few frames while the builder
     * fills the page, so the reveal is attempted on a short timer and given up
     * on rather than left running: a key that is on no page of this build (a row
     * that was renamed, say) must not keep a timer alive for the session. The
     * window covers a full page's build, the slowest of which is ~150ms.
     */
    Timer {
        id: revealTimer
        interval: 40
        onTriggered: {
            if (root.revealRow() || ++root.revealTries > 15)
                root.revealTries = 0;
            else
                revealTimer.restart();
        }
    }

    // Pinned to the bottom-right of the content area on every page, independent
    // of scroll position.
    SettingResetButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 28
        anchors.bottomMargin: 24
        onClicked: root.resetCurrentPage()
    }
}
