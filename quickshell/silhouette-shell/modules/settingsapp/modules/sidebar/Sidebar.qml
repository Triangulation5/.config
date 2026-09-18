import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.settingsapp.config
import qs.modules.settingsapp.pages
import qs.modules.settingsapp.modules.sidebar

/**
 * The rail: a search field over a scrolling page list. It owns the selection
 * (`currentIndex`), which the host binds the content area to, and knows nothing
 * about what a page contains — its model is `Pages.navEntries(query)`.
 *
 * Two kinds of row come out of that model: a page, and — while a query is live —
 * each of that page's settings that matched, indented under it. A page row says
 * "open this page"; a hit says "open this page *and show me this setting*", which
 * it reports as `rowRequested` rather than moving anything, exactly as the
 * content area's chevrons report a step: the selection is this rail's property,
 * and a row that assigned to it directly would be a second writer.
 *
 * The rows land directly in this ColumnLayout. Inside a plain Column the
 * `Layout.fillWidth` on each row would be ignored and every row would collapse
 * to zero width, which is how an empty rail happens.
 *
 * The list is a scroll view because the rail no longer fits on the window: at
 * twelve pages the last few were simply unreachable, and every page added from
 * here would have made that worse. The search field stays fixed above it, since
 * scrolling the field you are typing into away from the cursor is its own kind
 * of broken.
 *
 * The rail starts at its search field. A name header used to sit above it,
 * beside the icon this window wears in a launcher; both are gone. The name is
 * already what a dock, a taskbar and the pill's own window list print for this
 * dialog, and inside the window the rail's height is worth more to the pages:
 * a title that repeats the window's own identity costs a row of the list every
 * time the rail is open. The icon asset (`assets/silhouette-settings.svg`) stays
 * where it is — a desktop entry still points at it — but nothing in the window
 * draws it any more.
 *
 * The rail keeps the open page's row in view, and rolls to it when it is not:
 * the chevrons walk the pages without ever touching this list, so page eleven
 * can open with the rail still showing page one. The roll is the calendar's
 * wheel, borrowed — see `rollToCurrent`.
 */
Rectangle {
    id: root

    property int currentIndex: 0

    /** The live search query, following the field below. */
    property string query: search.text

    /**
     * The roll's pace. Longer than the window's own fades (`Theme.animNormal`,
     * 150): the pill's calendar rolls a week of days across in `Motion.fast *
     * 1.3`, and this is that gesture over a list of thirteen pages — long enough
     * to read as a wheel settling onto a page, short enough that a jump is never
     * something you wait on.
     */
    readonly property int rollMs: 300

    /** A rail row asking for the page at `pageIndex`, scrolled to `rowKey`. */
    signal pageSelected(int pageIndex)
    signal rowRequested(int pageIndex, string rowKey)

    readonly property var entries: Pages.navEntries(query)

    /**
     * The nav row of the open page, or null while the live query filters it out.
     *
     * The page index is compared here rather than read off the row's own
     * `current` — the same comparison, but made when it is asked for. A row's
     * `current` is a binding, and a `currentIndex` change is delivered to this
     * file's change handler *before* that binding has been re-evaluated, so the
     * scan would find the page the rail is leaving and roll back to it.
     */
    function selectedEntry() {
        for (var i = 0; i < navRepeater.count; i++) {
            var entry = navRepeater.itemAt(i);
            if (entry && entry.modelData.index === root.currentIndex)
                return entry;
        }
        return null;
    }

    /**
     * Bring the open page's row into view — the wheel's spin.
     *
     * A row that is already in view is left where it is: nothing should move for
     * a click you just made, and that is the common case. A row that is *not* in
     * view is rolled to the middle of the list rather than jammed against the
     * edge, so the pages either side of it come with it — the way the calendar's
     * wheel lands on today with the days around it. Nothing is rolled when the
     * query filters the open page out: `selectedEntry` finds no row, and the
     * rail has nothing to focus.
     */
    function rollToCurrent() {
        var entry = root.selectedEntry();
        var flick = list.contentItem;
        if (!entry || !flick)
            return;
        var y = entry.mapToItem(navColumn, 0, 0).y;
        var view = flick.height;
        /** A viewport with no height has not been laid out yet: there is no view
          * to roll into, and `Math.min` against a zero-height view would report
          * the end of the list as the only place the row could be seen. */
        if (view <= 0)
            return;
        // Wholly in view, edge to edge, is the one case that moves nothing — a
        // tolerance, not a comfort band: a row flush against either edge is
        // *seen*, and rolling to a row that is already there is what a click on
        // it would do to itself.
        if (y >= flick.contentY - 1 && y + entry.height <= flick.contentY + view + 1)
            return;
        roll.to = Math.max(0, Math.min(flick.contentHeight - view, y + entry.height / 2 - view / 2));
        roll.restart();
    }

    onCurrentIndexChanged: root.rollToCurrent()
    onEntriesChanged: rollTick.restart()
    Component.onCompleted: rollTick.restart()

    color: Theme.sidebar

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        spacing: 6

        SidebarSearch {
            id: search
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 8 }

        ScrollView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // No bar and no trough: the default Qt scrollbar is a light grey slab
            // that has nothing to do with this panel, and it is drawn as an
            // overlay *on* the rows. The list still scrolls — wheel, trackpad,
            // and a drag that started over it — and a cut-off row is the hint
            // that there is more below.
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: navColumn

                // The viewport's own width: a layout inside a scroll view is
                // handed its implicit width, which would leave the rows as wide
                // as their longest label and the highlight short of the edge.
                width: list.availableWidth
                spacing: 2

                Repeater {
                    id: navRepeater
                    model: root.entries

                    delegate: ColumnLayout {
                        id: entry

                        required property var modelData

                        /** This row is the open page's row. */
                        readonly property bool current: entry.modelData.index === root.currentIndex

                        Layout.fillWidth: true
                        spacing: 0

                        SidebarItem {
                            Layout.fillWidth: true
                            label: entry.modelData.page.name
                            icon: entry.modelData.page.icon
                            // modelData.index is the page's real position in
                            // the index, so a filtered rail still opens the page
                            // it shows rather than the row's position in the
                            // filter.
                            selected: entry.current
                            onClicked: root.pageSelected(entry.modelData.index)
                        }

                        Repeater {
                            model: entry.modelData.hits

                            delegate: SidebarHit {
                                id: hit

                                required property var modelData

                                Layout.fillWidth: true
                                label: hit.modelData.label
                                onClicked: root.rowRequested(entry.modelData.index, Pages.rowKey(hit.modelData))
                            }
                        }
                    }
                }

                // Nothing matched the query: say so instead of leaving a silent
                // gap where the nav list used to be.
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    visible: root.entries.length === 0
                    text: "No settings match \u201C" + root.query.trim() + "\u201D"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    /**
     * The spin itself: the calendar's opening sweep, borrowed. A short OutBack
     * with overshoot, so the list carries a wheel's weight and settles onto the
     * page rather than snapping to it — a roll past either end of the list is
     * stopped by the flickable's own bounds.
     *
     * Animating `contentY` directly (rather than asking the flickable to flick)
     * keeps the pace ours, and bypasses a drag the pointer may be in the middle
     * of.
     */
    NumberAnimation {
        id: roll
        target: list.contentItem
        property: "contentY"
        duration: root.rollMs
        easing.type: Easing.OutBack
        easing.overshoot: 0.8
    }

    /**
     * The roll is asked for a tick late wherever the rows may have just moved:
     * a delegate rebuilt by a query, or by the window's first build, has no
     * position until a layout pass has run over it, and measuring one before
     * that reads a row sitting at y=0.
     */
    Timer {
        id: rollTick
        interval: 40
        onTriggered: root.rollToCurrent()
    }

    // Divider between the rail and the content area.
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }
}
