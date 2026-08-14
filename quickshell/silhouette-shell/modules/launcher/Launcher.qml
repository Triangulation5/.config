pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.controls
import "../../utils/launcher/fuzzy.js" as Fuzzy
import "../../utils/launcher/calc.js" as Calc
import "../../utils/launcher/emojis.js" as EmojiData

/**
 * Launcher surface: search field over a ranked application list, drawn as one
 * of the pill's surfaces. Desktop entries are ranked by fuzzy match and prior
 * launch frequency (usage file shared with the standalone launcher), the
 * chosen entry executes directly.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 11
    mRight: 11
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0
    property var usage: ({})
    property var entries: []
    property int total: 0

    signal launch(var entry)
    signal quit()

    /**
     * Calc mode: when the whole query parses as a real calculation (an
     * expression with at least one operation, so lone numbers and app names like
     * i3 or python3 fall through to app search), a result row appears above the
     * list and Enter copies the value. The parser in utils/launcher/calc.js never
     * evals, so a query cannot run code.
     */
    readonly property var calc: Calc.evaluate(query)
    readonly property bool calcActive: calc.ok
    property bool calcCopied: false
    property bool emojiCopied: false
    onQueryChanged: { calcCopied = false; emojiCopied = false; }

    function copyResult() {
        if (!root.calcActive)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", root.calc.display]);
        root.calcCopied = true;
    }

    /**
     * AI mode: an `@` prefix opens Perplexity in Firefox with the query
     * pre-filled and submitted via the `q=` URL parameter. Reuses an
     * existing Firefox window as a new tab if one is already running.
     */
    readonly property bool aiActive: query.length > 1 && query[0] === '@'
    readonly property string aiQuery: aiActive ? query.slice(1).trim() : ""

    function runAI() {
        if (!aiActive || aiQuery.length === 0)
            return;

        const url = "https://www.perplexity.ai/search?q=" + encodeURIComponent(aiQuery);
        Quickshell.execDetached(["firefox", "--new-tab", url]);

        requestClose();
    }

    /**
     * Command palette mode: a `>` prefix turns the launcher into a raycast-style
     * palette. Currently supports web search via Firefox.
     */
    readonly property bool commandActive: query.length > 1 && query[0] === '>'
    readonly property string commandQuery: commandActive ? query.slice(1).trim() : ""

    function runWebSearch() {
        if (!root.commandActive || root.commandQuery.length === 0)
            return;
        Quickshell.execDetached(["firefox", "--search", root.commandQuery]);
        root.quit();
        root.requestClose();
    }

    /**
     * Terminal mode: a `$` prefix turns the launcher into a terminal command
     * runner. The query is launched via kitty so CLI apps like btop or nvim
     * open in their own terminal window.
     */
    readonly property bool terminalActive: query.length > 1 && query[0] === '$'
    readonly property string terminalCommand: terminalActive ? query.slice(1).trim() : ""

    function runInTerminal() {
        if (!root.terminalActive || root.terminalCommand.length === 0)
            return;
        Quickshell.execDetached(["kitty", "bash", "-c", root.terminalCommand + "; exec $SHELL"]);
        root.quit();
        root.requestClose();
    }

    /**
     * Window switcher mode: a `:w` prefix shows open Hyprland windows filtered
     * by title/class. Enter focuses the selected window and closes.
     */
    readonly property bool windowActive: query.length >= 2 && query[0] === ':' && query[1] === 'w'
        && (query.length === 2 || query[2] === ' ')
    readonly property string windowQuery: windowActive ? (query.length > 3 ? query.slice(3).trim() : "") : ""

    /**
     * Emoji picker mode: a `:` prefix (not `:w`) shows emojis filtered by name.
     * Enter copies the selected emoji via wl-copy and closes.
     */
    readonly property bool emojiActive: query.length > 1 && query[0] === ':' && !root.windowActive
    readonly property string emojiQuery: emojiActive ? query.slice(1).trim() : ""

    readonly property var emojiResults: {
        var q = root.emojiQuery.toLowerCase();
        if (q.length === 0)
            return EmojiData.Emojis;
        var out = [];
        for (var i = 0; i < EmojiData.Emojis.length; i++) {
            if (EmojiData.Emojis[i].n.indexOf(q) !== -1)
                out.push(EmojiData.Emojis[i]);
        }
        return out;
    }

    readonly property var windowResults: {
        var tl = Hyprland.toplevels.values;
        var out = [];
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (!t || !t.address || !t.title)
                continue;
            var ipc = t.lastIpcObject;
            out.push({
                address: t.address,
                title: t.title || "",
                cls: (ipc && ipc.class) ? ipc.class : "",
                workspace: (ipc && ipc.workspace) ? ipc.workspace.name : ""
            });
        }
        var q = root.windowQuery.toLowerCase();
        if (q.length === 0)
            return out;
        var filtered = [];
        for (var j = 0; j < out.length; j++) {
            var w = out[j];
            if (w.title.toLowerCase().indexOf(q) !== -1 || w.cls.toLowerCase().indexOf(q) !== -1)
                filtered.push(w);
        }
        return filtered;
    }

    function iconForWindow(cls) {
        if (!cls || !cls.length)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (!a || !a.id)
                continue;
            var id = a.id.toLowerCase();
            if (id === cls.toLowerCase() + ".desktop" || id.indexOf(cls.toLowerCase() + ".desktop") === 0)
                return a.icon ? Quickshell.iconPath(a.icon, true) : "";
        }
        return "";
    }

    function copyEmoji() {
        if (!root.emojiActive || root.emojiResults.length === 0 || selectedIndex < 0 || selectedIndex >= root.emojiResults.length)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", root.emojiResults[selectedIndex].e]);
        root.emojiCopied = true;
        root.quit();
        root.requestClose();
    }

    function focusWindow() {
        if (!root.windowActive || root.windowResults.length === 0 || selectedIndex < 0 || selectedIndex >= root.windowResults.length)
            return;
        var addr = root.windowResults[selectedIndex].address;
        if (addr.indexOf("0x") !== 0)
            addr = "0x" + addr;
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })');
        root.quit();
        root.requestClose();
    }

    /** Row index currently in AppImage edit mode (rename plus armed delete), -1 when none. */
    property int editIndex: -1

    readonly property string appimageScript: Quickshell.env("HOME") + "/.config/hypr/scripts/app-install.sh"

    function appimageSlug(entry) {
        return entry && entry.id && entry.id.indexOf("ricelin-") === 0 ? entry.id.substring(8) : "";
    }

    Process { id: appimageProc }

    /**
     * Window-coordinate position of the last hover event that was allowed to
     * move the selection. Rows sliding under a stationary cursor during
     * keyboard scrolling produce hover events at an unchanged window position,
     * which must not steal the keyboard selection.
     */
    property point lastPointer: Qt.point(-1, -1)

    ameForm: "caret"
    amePoint: caretPointOf(search.input)

    readonly property string usageFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/launcher-usage.json"

    readonly property var allEntries: {
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && !src[i].noDisplay) out.push(src[i]);
        return out;
    }
    readonly property int totalCount: allEntries.length
    readonly property var results: (entries && entries.length > 0) ? entries : Fuzzy.rank(allEntries, query, usage)

    function focusField() { search.input.forceActiveFocus(); }

    function mapCategory(raw) {
        const order = [
            ["TerminalEmulator", "Terminal"], ["WebBrowser", "Browser"],
            ["InstantMessaging", "Chat"], ["Audio", "Media"], ["AudioVideo", "Media"],
            ["Video", "Media"], ["Game", "Game"], ["Development", "Dev"],
            ["Graphics", "Graphics"], ["Office", "Office"], ["Settings", "System"],
            ["System", "System"], ["Utility", "Tool"], ["Network", "Net"]
        ];
        const cats = String(raw).split(/[;,]/);
        for (let i = 0; i < order.length; i++)
            if (cats.includes(order[i][0]))
                return order[i][1];
        return "";
    }

    function move(delta) {
        if (root.windowActive) {
            if (root.windowResults.length === 0)
                return;
            selectedIndex = Math.max(0, Math.min(root.windowResults.length - 1, selectedIndex + delta));
            winList.positionViewAtIndex(selectedIndex, ListView.Contain);
            return;
        }
        if (root.emojiActive) {
            if (root.emojiResults.length === 0)
                return;
            selectedIndex = Math.max(0, Math.min(root.emojiResults.length - 1, selectedIndex + delta));
            emojiGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
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
            if (root.entries && root.entries.length > 0) {
                root.launch(entry);
            } else {
                if (entry.id) {
                    root.usage[entry.id] = (root.usage[entry.id] || 0) + 1;
                    usageStore.setText(JSON.stringify(root.usage));
                }
                entry.execute();
            }
        }
        root.quit();
        root.requestClose();
    }

    onActiveChanged: {
        if (active) {
            query = "";
            search.text = "";
            selectedIndex = 0;
            Qt.callLater(root.focusField);
        }
    }
    onResultsChanged: {
        if (selectedIndex >= results.length)
            selectedIndex = 0;
        editIndex = -1;
    }
    onEmojiResultsChanged: {
        if (selectedIndex >= root.emojiResults.length)
            selectedIndex = 0;
    }
    onWindowResultsChanged: {
        if (selectedIndex >= root.windowResults.length)
            selectedIndex = 0;
    }

    FileView {
        id: usageStore
        path: root.usageFile
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    Component.onCompleted: {
        var raw = usageStore.text();
        try {
            root.usage = raw && raw.length ? JSON.parse(raw) : ({});
        } catch (e) {
            root.usage = ({});
        }
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
        onDismissed: { root.quit(); root.requestClose(); }
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

    /** ── Emoji grid ── */

    EmojiGrid {
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        s: root.s
        host: root
    }

    /** ── Window list ── */

    WinList {
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        s: root.s
        host: root
    }

    /** ── App list ── */

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
            editing: { var e = root.results[index]; return e && e.id && e.id.indexOf("ricelin-") === 0 && root.editIndex === index; }
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
