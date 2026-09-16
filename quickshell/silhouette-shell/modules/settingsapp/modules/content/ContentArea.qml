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

    /** First row of each card within the page, for `visibleRows` below. */
    property var groupOffsets: []

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
     * Open a page from empty: record where each card's rows begin and let the
     * builder fill them in. Resetting `builtRows` is what empties the previous
     * page — a page that is not open holds no items, which is the lazy half of
     * this file.
     */
    function startPage() {
        var offsets = [];
        var running = 0;
        for (var g = 0; g < root.pageGroups.length; g++) {
            offsets.push(running);
            running += root.pageGroups[g].rows.length;
        }
        root.groupOffsets = offsets;
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
                         * How many of this card's rows have been built. The
                         * subtraction is read on `builtRows`, so the binding
                         * follows the builder; `groupOffsets` is a property
                         * rather than a call because a binding cannot see
                         * through a function.
                         */
                        visibleRows: Math.max(0, Math.min(modelData.rows.length,
                                                          root.builtRows - root.groupOffsets[index]))
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
     * in one pass: each pass adds rows until 6ms have gone, so cheap rows land
     * together (most pages are done in two or three frames) and an expensive one
     * cannot blow the frame budget on its own. Nothing is built for a page that
     * is not open, and the pass stops on its own once the page is full.
     */
    Timer {
        id: rowBuilder
        interval: 1
        repeat: true
        running: root.builtRows < root.pageRows.length
        onTriggered: {
            var deadline = Date.now() + 6;
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
