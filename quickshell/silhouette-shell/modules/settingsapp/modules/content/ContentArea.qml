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
 * reveal is retried briefly rather than done once, because the row belongs to a
 * delegate that is built *because* the page just changed — the first frames
 * after a switch have no such item to measure.
 */
Item {
    id: root

    property int pageIndex: 0

    /** The flag key or config field of the row to show, or "" for no target. */
    property string targetKey: ""

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
     * are not there yet, which is what makes the retry timer worth having.
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
    onPageIndexChanged: if (root.targetKey.length > 0) root.scheduleReveal()

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
                    model: root.pageView === null && root.page ? root.page.groups : []

                    delegate: SettingGroup {
                        required property var modelData
                        group: modelData
                        targetKey: root.targetKey
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    visible: root.pageView !== null
                    source: root.pageView !== null ? root.pageView : ""
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
     * A page switch lands the delegates a frame or two later, so the reveal is
     * attempted on a short timer and given up on rather than left running: a key
     * that is on no page of this build (a row that was renamed, say) must not
     * keep a timer alive for the session.
     */
    Timer {
        id: revealTimer
        interval: 60
        onTriggered: {
            if (root.revealRow() || ++root.revealTries > 5)
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
