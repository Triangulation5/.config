pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls
import "../../utils/launcher/fuzzy.js" as Fuzzy
import "../../utils/launcher/calc.js" as Calc

/**
 * Launcher surface: search field over a ranked application list, drawn as one
 * of the pill's surfaces (or hosted inside `LauncherRoot` as a full-screen
 * overlay). Desktop entries, usage frequency persistence, and crash-guarded /
 * terminal-aware launching are provided by `services/AppLauncher.qml`; emoji
 * and window modes are split into `EmojiSearch.qml` and `WindowSearch.qml`.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 11
    mRight: 11
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0
    /** Optional externally ranked list (supplied by `LauncherRoot`). Null when self-driven in the pill. */
    property var entries: null
    property int total: 0

    signal launch(var entry)
    signal quit()

    /**
     * The pill hosting this surface, when this is the pill's own launcher
     * (Pill.qml passes it through surfaceProps). Null for the standalone
     * launcher window, which has no pill to hand back.
     */
    property var pillRef: null

    readonly property bool externalMode: root.entries !== null

    function finish() {
        if (pillRef)
            pillRef.dismissHover();
        quit();
        requestClose();
    }

    /** Calc mode: active when the query parses as an expression with at least one operation. */
    readonly property var calc: Calc.evaluate(query)
    readonly property bool calcActive: calc.ok
    property bool calcCopied: false
    readonly property bool emojiCopied: emojiSearch.copied
    onQueryChanged: {
        calcCopied = false;
        if (!root.externalMode && root.active)
            LauncherMatch.sendQuery(root.query);
    }

    function copyResult() {
        if (!root.calcActive)
            return;
        Quickshell.execDetached(["wl-copy", "--", root.calc.display]);
        root.calcCopied = true;
    }

    /** AI mode (`@` prefix): open Perplexity search in Firefox. */
    readonly property bool aiActive: query.length > 1 && query[0] === '@'
    readonly property string aiQuery: aiActive ? query.slice(1).trim() : ""

    function runAI() {
        if (!aiActive || aiQuery.length === 0)
            return;
        const url = "https://www.perplexity.ai/search?q=" + encodeURIComponent(aiQuery);
        Quickshell.execDetached(["firefox", "--new-tab", url]);
        root.finish();
    }

    /** Command palette mode (`>` prefix): web search via Firefox. */
    readonly property bool commandActive: query.length > 1 && query[0] === '>'
    readonly property string commandQuery: commandActive ? query.slice(1).trim() : ""

    function runWebSearch() {
        if (!root.commandActive || root.commandQuery.length === 0)
            return;
        Quickshell.execDetached(["firefox", "--search", root.commandQuery]);
        root.finish();
    }

    /** Terminal mode (`$` prefix): run a command inside kitty. */
    readonly property bool terminalActive: query.length > 1 && query[0] === '$'
    readonly property string terminalCommand: terminalActive ? query.slice(1).trim() : ""

    function runInTerminal() {
        if (!root.terminalActive || root.terminalCommand.length === 0)
            return;
        Quickshell.execDetached(["kitty", "bash", "-c", root.terminalCommand + "; exec $SHELL"]);
        root.finish();
    }

    /** Window switcher mode (`:w` prefix). */
    readonly property bool windowActive: query.length >= 2 && query[0] === ':' && query[1] === 'w'
        && (query.length === 2 || query[2] === ' ')
    readonly property string windowQuery: windowActive ? (query.length > 3 ? query.slice(3).trim() : "") : ""

    /** Emoji picker mode (`:` prefix, excluding `:w`). */
    readonly property bool emojiActive: query.length > 1 && query[0] === ':' && !root.windowActive
    readonly property string emojiQuery: emojiActive ? query.slice(1).trim() : ""

    EmojiSearch {
        id: emojiSearch
        active: root.emojiActive
        query: root.emojiQuery
        onResultsChanged: {
            if (root.selectedIndex >= emojiSearch.results.length)
                root.selectedIndex = 0;
        }
    }

    WindowSearch {
        id: windowSearch
        active: root.windowActive
        query: root.windowQuery
        onResultsChanged: {
            if (root.selectedIndex >= windowSearch.results.length)
                root.selectedIndex = 0;
        }
    }

    readonly property var emojiResults: emojiSearch.results
    readonly property var windowResults: windowSearch.results

    function iconForWindow(cls) {
        return windowSearch.iconForWindow(cls);
    }

    function copyEmoji() {
        if (emojiSearch.copyAt(root.selectedIndex))
            root.finish();
    }

    function focusWindow() {
        if (windowSearch.focusAt(root.selectedIndex))
            root.finish();
    }

    /** Row index currently in AppImage edit mode (rename plus armed delete), -1 when none. */
    property int editIndex: -1

    readonly property string appimageScript: AppLauncher.appimageScript
    readonly property alias appimageProc: appimageProc
    Process { id: appimageProc }

    function launchApp(entry) {
        AppLauncher.launch(entry);
    }

    function appimageSlug(entry) {
        return AppLauncher.appimageSlug(entry);
    }

    function mapCategory(raw) {
        return AppLauncher.mapCategory(raw);
    }

    /**
     * Window-coordinate position of the last hover event allowed to move the
     * selection so keyboard scrolling under a stationary cursor cannot steal it.
     */
    property point lastPointer: Qt.point(-1, -1)

    ameForm: "caret"
    amePoint: caretPointOf(search.input)

    readonly property var allEntries: AppLauncher.allEntries
    readonly property int totalCount: root.externalMode ? root.total : AppLauncher.total
    readonly property var results: {
        if (root.externalMode)
            return root.entries;
        void LauncherMatch.lastSeq;
        var rust = LauncherMatch.resolve(AppLauncher.allEntries);
        return rust !== null ? rust : Fuzzy.rank(AppLauncher.allEntries, root.query, AppLauncher.usage);
    }

    Connections {
        target: AppLauncher
        function onAllEntriesChanged() {
            if (!root.externalMode && root.active)
                LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
        }
        function onUsageChanged() {
            if (!root.externalMode && root.active)
                LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
        }
    }

    function focusField() { search.input.forceActiveFocus(); }

    function move(delta) {
        if (root.windowActive) {
            if (root.windowResults.length === 0)
                return;
            selectedIndex = Math.max(0, Math.min(root.windowResults.length - 1, selectedIndex + delta));
            winListView.scrollTo(selectedIndex);
            return;
        }
        if (root.emojiActive) {
            if (root.emojiResults.length === 0)
                return;
            selectedIndex = Math.max(0, Math.min(root.emojiResults.length - 1, selectedIndex + delta));
            emojiGridView.scrollTo(selectedIndex);
            return;
        }
        if (results.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activate() {
        if (root.aiActive) {
            root.runAI();
            return;
        }
        if (root.commandActive) {
            root.runWebSearch();
            return;
        }
        if (root.terminalActive) {
            root.runInTerminal();
            return;
        }
        if (root.windowActive) {
            root.focusWindow();
            return;
        }
        if (root.emojiActive) {
            root.copyEmoji();
            return;
        }
        if (root.calcActive) {
            root.copyResult();
            return;
        }
        if (results.length === 0 || selectedIndex < 0 || selectedIndex >= results.length)
            return;
        var entry = results[selectedIndex];
        if (entry) {
            if (root.externalMode)
                root.launch(entry);
            else
                AppLauncher.launchAndRecord(entry);
        }
        root.finish();
    }

    onActiveChanged: {
        if (!root.externalMode) {
            LauncherMatch.setConsumer("pill", root.active);
            if (root.active) {
                AppLauncher.reloadUsage();
                LauncherMatch.sync(AppLauncher.allEntries, "", AppLauncher.usage);
            }
        }
        if (active) {
            query = "";
            search.text = "";
            selectedIndex = 0;
            Qt.callLater(root.focusField);
        }
    }
    Component.onDestruction: {
        if (!root.externalMode)
            LauncherMatch.setConsumer("pill", false);
    }
    onResultsChanged: {
        if (selectedIndex >= results.length)
            selectedIndex = 0;
        editIndex = -1;
    }

    SearchField {
        id: search
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        kanji: "探"
        placeholder: "Search apps"
        counterText: root.aiActive ? "@" : (root.commandActive ? "⌘" : (root.terminalActive ? "$" : (root.windowActive ? (root.windowResults.length + " windows") : (root.emojiActive ? ":" : (root.results.length + " / " + root.totalCount)))))
        onTextChanged: {
            root.query = text;
            root.selectedIndex = 0;
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: root.finish()
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

    CalcRow {
        id: calcRow
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        host: root
    }

    ModeRows {
        id: modeRows
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        host: root
    }

    Text {
        anchors.centerIn: list
        visible: root.results.length === 0 && !root.calcActive && !root.aiActive && !root.commandActive && !root.terminalActive && !root.emojiActive && !root.windowActive
        text: root.query.length ? "No matches" : "No apps found"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    EmojiGrid {
        id: emojiGridView
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        s: root.s
        host: root
    }

    WinList {
        id: winListView
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        s: root.s
        host: root
    }

    ListView {
        id: list
        visible: !root.aiActive && !root.commandActive && !root.terminalActive && !root.emojiActive && !root.windowActive
        anchors.top: root.calcActive ? calcRow.bottom
            : (modeRows.active ? modeRows.bottom : divider.bottom)
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hint.visible ? hint.top : parent.bottom
        anchors.bottomMargin: hint.visible ? 4 * root.s : 0
        spacing: 5 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results.length

        delegate: AppRow {
            required property int index
            surface: root
            s: root.s
            entry: root.results[index]
            selected: root.selectedIndex === index
            /** Coerced to a real bool: a missing entry would otherwise leave the
             *  expression undefined, which QML logs as an invalid assignment. */
            editing: { var e = root.results[index]; return !!(e && AppLauncher.isAppImage(e) && root.editIndex === index); }
        }
    }

    /** Faint nudge so the drag-to-install gesture is discoverable at all. */
    Row {
        id: hint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2 * root.s
        spacing: 5 * root.s
        visible: root.query.length === 0 && root.editIndex === -1 && !root.emojiActive && !root.windowActive
        opacity: 0.6

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 12 * root.s
            height: 12 * root.s
            stroke: 1.7
            name: "download"
            color: Theme.faint
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Drag an AppImage onto the pill"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }
    }
}
