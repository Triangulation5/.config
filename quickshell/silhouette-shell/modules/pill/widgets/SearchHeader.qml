pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.launcher

/**
 * Shared search header for picker surfaces (launcher, emoji, window switcher).
 * Owns the SearchField, divider, caret-flame mapping, query/index state, and
 * the keyboard navigation primitives (move, focusField). Wire the parent
 * surface's `active` to `surfaceActive` so the field clears and refocuses on
 * every open. Connect `onActivate` and `onDismiss` to the parent's
 * Enter/Escape actions. Bind `results` to the parent's filtered list so the
 * index guard on results-changed stays in one place.
 *
 * The parent renders its own results area below this header and implements its
 * own `activate()` — that's where the selected item is acted on.
 */
Item {
    id: root

    property real s: 1.1
    property string kanji: ""
    property string placeholder: ""
    property string counterText: ""
    property var results: []
    property bool surfaceActive: false

    property string query: ""
    property int selectedIndex: 0

    /** Emitted when the parent should act on the selected result. */
    signal activate()
    /** Emitted when the surface should close. */
    signal dismiss()

    function focusField() { search.input.forceActiveFocus(); }

    function move(delta) {
        if (root.results.length === 0)
            return;
        root.selectedIndex = Math.max(0, Math.min(root.results.length - 1, root.selectedIndex + delta));
    }

    onSurfaceActiveChanged: {
        if (surfaceActive) {
            query = "";
            search.text = "";
            selectedIndex = 0;
            Qt.callLater(root.focusField);
        }
    }

    onResultsChanged: {
        if (selectedIndex >= results.length)
            selectedIndex = 0;
    }

    readonly property point caretPos: {
        void root.width;
        void root.height;
        void search.input.width;
        return search.input.mapToItem(root,
            search.input.cursorRectangle.x + search.input.cursorRectangle.width / 2,
            search.input.cursorRectangle.y + search.input.cursorRectangle.height / 2);
    }

    implicitHeight: search.height + 8 * root.s + divider.height

    SearchField {
        id: search
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        kanji: root.kanji
        placeholder: root.placeholder
        counterText: root.counterText
        onTextChanged: {
            root.query = text;
            root.selectedIndex = 0;
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: root.dismiss()
    }

    Rectangle {
        id: divider
        anchors.top: search.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }
}
