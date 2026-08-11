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
        Quickshell.execDetached(["kitty", "--", "bash", "-c", root.terminalCommand + "; exec $SHELL"]);
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

    readonly property point caretPoint: {
        void root.width;
        void root.height;
        void search.input.width;
        return search.input.mapToItem(root,
            search.input.cursorRectangle.x + search.input.cursorRectangle.width / 2,
            search.input.cursorRectangle.y + search.input.cursorRectangle.height / 2);
    }
    readonly property real caretX: caretPoint.x
    readonly property real caretY: caretPoint.y

    ameForm: "caret"
    amePoint: Qt.point(caretX, caretY)

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
        counterText: root.commandActive ? "⌘" : (root.terminalActive ? "$" : (root.windowActive ? (root.windowResults.length + " windows") : (root.emojiActive ? ":" : (root.results.length + " / " + root.totalCount))))
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

    Item {
        id: calcRow
        visible: root.calcActive
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 44 * root.s : 0

        Rectangle {
            anchors.fill: parent
            radius: 9 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: Theme.frameBorder
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.copyResult()
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s

            Column {
                anchors.left: parent.left
                anchors.right: copyHint.left
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Text {
                    width: parent.width
                    text: "= " + root.calc.display
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 15 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.query
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    elide: Text.ElideRight
                }
            }

            Text {
                id: copyHint
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.calcCopied ? "copied" : "↵ copy"
                color: root.calcCopied ? Theme.dim : Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
    }

    Item {
        id: commandRow
        visible: root.commandActive
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 44 * root.s : 0

        Rectangle {
            anchors.fill: parent
            radius: 9 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: Theme.frameBorder
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runWebSearch()
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s

            GlyphIcon {
                id: cmdGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18 * root.s
                height: 18 * root.s
                name: "search"
                color: Theme.vermLit
                stroke: 1.7
            }

            Column {
                anchors.left: cmdGlyph.right
                anchors.leftMargin: 10 * root.s
                anchors.right: cmdHint.left
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Text {
                    width: parent.width
                    text: "Search the web"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 13.5 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.commandQuery
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    elide: Text.ElideRight
                }
            }

            Text {
                id: cmdHint
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↵ search"
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
    }

    Item {
        id: terminalRow
        visible: root.terminalActive
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 44 * root.s : 0

        Rectangle {
            anchors.fill: parent
            radius: 9 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: Theme.frameBorder
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runInTerminal()
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s

            GlyphIcon {
                id: termGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 18 * root.s
                height: 18 * root.s
                name: "terminal"
                color: Theme.vermLit
                stroke: 1.7
            }

            Column {
                anchors.left: termGlyph.right
                anchors.leftMargin: 10 * root.s
                anchors.right: termHint.left
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Text {
                    width: parent.width
                    text: "Run in terminal"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 13.5 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.terminalCommand
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    elide: Text.ElideRight
                }
            }

            Text {
                id: termHint
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↵ run"
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: root.results.length === 0 && !root.calcActive && !root.commandActive && !root.terminalActive && !root.emojiActive && !root.windowActive
        text: root.query.length ? "No matches" : "No apps found"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    /** ── Emoji grid ── */

    GridView {
        id: emojiGrid
        visible: root.emojiActive
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: 40 * root.s
        cellHeight: 40 * root.s
        model: root.emojiResults.length
        currentIndex: root.selectedIndex

        delegate: Rectangle {
            required property int index
            width: emojiGrid.cellWidth - 2 * root.s
            height: emojiGrid.cellHeight - 2 * root.s
            radius: 8 * root.s
            color: index === root.selectedIndex ? Theme.frameBg : (emoArea.containsMouse ? Qt.rgba(0.94, 0.88, 0.84, 0.04) : "transparent")
            border.width: index === root.selectedIndex ? 1 : 0
            border.color: Theme.frameBorder

            readonly property var emoji: root.emojiResults[index]

            Text {
                anchors.centerIn: parent
                text: parent.emoji ? parent.emoji.e : ""
                font.pixelSize: 22 * root.s
            }

            MouseArea {
                id: emoArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.selectedIndex = index;
                    root.copyEmoji();
                }
                onEntered: root.selectedIndex = index
            }
        }

        WheelScroller {
            anchors.fill: parent
            s: root.s
            flick: emojiGrid
        }
    }

    /** Emoji name label bar when emoji mode is active. */
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        width: nameLabel.implicitWidth + 20 * root.s
        height: visible ? 22 * root.s : 0
        radius: 6 * root.s
        color: Qt.rgba(0, 0, 0, 0.4)
        visible: root.emojiActive && root.emojiResults.length > 0 && root.selectedIndex < root.emojiResults.length

        Text {
            id: nameLabel
            anchors.centerIn: parent
            text: root.emojiCopied ? "Copied!" : (root.emojiResults[root.selectedIndex] ? root.emojiResults[root.selectedIndex].n : "")
            color: root.emojiCopied ? Theme.vermLit : Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }
    }

    /** ── Window list ── */

    Text {
        anchors.centerIn: winList
        visible: root.windowActive && root.windowResults.length === 0
        text: root.windowQuery.length ? "No windows match" : "No windows open"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
    }

    ListView {
        id: winList
        visible: root.windowActive
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 5 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.windowResults.length

        delegate: Item {
            id: winRow
            required property int index
            width: winList.width
            height: 38 * root.s

            readonly property var win: root.windowResults[index]
            readonly property bool selected: index === root.selectedIndex
            readonly property string resolvedIcon: root.iconForWindow(winRow.win.cls)

            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                visible: winRow.selected || winArea.containsMouse
                color: winRow.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
                border.width: winRow.selected ? 1 : 0
                border.color: Theme.frameBorder
            }

            MouseArea {
                id: winArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = winRow.index
                onClicked: {
                    root.selectedIndex = winRow.index;
                    root.focusWindow();
                }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 11 * root.s
                anchors.rightMargin: 11 * root.s

                Rectangle {
                    id: winIconBg
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: 5 * root.s
                    color: Qt.rgba(1, 1, 1, 0.05)
                    visible: !(winIcon.status === Image.Ready && winIcon.source != "")
                }
                Image {
                    id: winIcon
                    anchors.fill: winIconBg
                    sourceSize.width: Math.round(40 * root.s)
                    sourceSize.height: Math.round(40 * root.s)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready && source != ""
                    source: winRow.resolvedIcon
                }
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: winIconBg.horizontalCenter
                    width: 14 * root.s
                    height: 14 * root.s
                    name: "window"
                    color: winRow.selected ? Theme.dim : Theme.faint
                    stroke: 1.7
                    visible: winRow.resolvedIcon.length === 0 || (winIcon.status !== Image.Ready)
                }

                Column {
                    anchors.left: winIconBg.right
                    anchors.leftMargin: 10 * root.s
                    anchors.right: wsPill.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * root.s

                    Text {
                        width: parent.width
                        text: winRow.win.title
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: winRow.selected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: winRow.win.cls.length > 0
                        text: winRow.win.cls
                        color: winRow.selected ? Theme.dim : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: wsPill
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: winRet.left
                    anchors.rightMargin: winRow.selected ? 6 * root.s : 0
                    width: visible ? wsLabel.implicitWidth + 10 * root.s : 0
                    height: 18 * root.s
                    radius: 4 * root.s
                    color: winRow.selected ? Qt.rgba(0.94, 0.88, 0.84, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    visible: winRow.win.workspace.length > 0 && winRow.win.workspace !== "special:minimized"

                    Text {
                        id: wsLabel
                        anchors.centerIn: parent
                        text: winRow.win.workspace
                        color: winRow.selected ? Theme.dim : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                    }
                }

                Text {
                    id: winRet
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "↵"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    visible: winRow.selected
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: winList
        visible: root.windowActive
        s: root.s
        flick: winList
    }

    /** ── App list ── */

    ListView {
        id: list
        visible: !root.commandActive && !root.terminalActive && !root.emojiActive && !root.windowActive
        anchors.top: root.calcActive ? calcRow.bottom
            : (root.commandActive ? commandRow.bottom
            : (root.terminalActive ? terminalRow.bottom : divider.bottom))
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hint.visible ? hint.top : parent.bottom
        anchors.bottomMargin: hint.visible ? 4 * root.s : 0
        spacing: 5 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results.length

        delegate: Item {
            id: appRow
            required property int index
            width: list.width
            height: 38 * root.s

            readonly property var entry: root.results[index]
            readonly property bool selected: index === root.selectedIndex
            readonly property bool isAppImage: entry && entry.id && entry.id.indexOf("ricelin-") === 0
            readonly property bool editing: root.editIndex === index && isAppImage
            property bool armed: false
            onEditingChanged: if (!editing) armed = false

            readonly property string secondary: {
                if (!entry)
                    return "";
                if (entry.genericName && entry.genericName.length > 0)
                    return entry.genericName;
                if (entry.categories && entry.categories.length > 0)
                    return root.mapCategory(entry.categories);
                return "";
            }

            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                visible: appRow.selected || rowArea.containsMouse
                color: appRow.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
                border.width: appRow.selected ? 1 : 0
                border.color: Theme.frameBorder
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (m) => {
                    var g = rowArea.mapToItem(null, m.x, m.y);
                    if (g.x !== root.lastPointer.x || g.y !== root.lastPointer.y) {
                        root.lastPointer = Qt.point(g.x, g.y);
                        root.selectedIndex = appRow.index;
                    }
                }
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) {
                        if (appRow.isAppImage)
                            root.editIndex = appRow.editing ? -1 : appRow.index;
                        return;
                    }
                    if (appRow.editing)
                        return;
                    root.selectedIndex = appRow.index;
                    root.activate();
                }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 11 * root.s
                anchors.rightMargin: 11 * root.s

                Rectangle {
                    id: iconBg
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: 5 * root.s
                    color: Qt.rgba(1, 1, 1, 0.05)
                    visible: !(icon.status === Image.Ready && icon.source != "")
                }
                Image {
                    id: icon
                    anchors.fill: iconBg
                    sourceSize.width: Math.round(40 * root.s)
                    sourceSize.height: Math.round(40 * root.s)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready && source != ""
                    source: {
                        if (!appRow.entry || !appRow.entry.icon)
                            return "";
                        var ic = appRow.entry.icon;
                        if (appRow.isAppImage && ic.indexOf("/") === 0)
                            return "file://" + ic;
                        return Quickshell.iconPath(ic, true);
                    }
                }

                TextMetrics {
                    id: retMetrics
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    text: "↵"
                }
                Text {
                    id: ret
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: retMetrics.text
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    visible: appRow.selected && !appRow.editing
                    width: visible ? retMetrics.advanceWidth + 6 * root.s : 0
                    horizontalAlignment: Text.AlignRight
                }

                GlyphIcon {
                    id: trashGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    width: appRow.editing ? 16 * root.s : 0
                    height: 16 * root.s
                    visible: appRow.editing
                    stroke: 2
                    name: "trash"
                    color: appRow.armed ? "#e0533f" : Theme.dim

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        enabled: appRow.editing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!appRow.armed) {
                                appRow.armed = true;
                                return;
                            }
                            var slug = root.appimageSlug(appRow.entry);
                            if (slug) {
                                appimageProc.command = ["bash", root.appimageScript, "remove", slug];
                                appimageProc.running = true;
                            }
                            root.editIndex = -1;
                        }
                    }
                }

                /**
                 * Name over description, each clipped on its own line, so a long
                 * comment can no longer bleed into the name the way one shared row
                 * let it. The block centres on the icon whether it shows one line or
                 * two, and an app with no description just reads as a centred name.
                 */
                Column {
                    anchors.left: iconBg.right
                    anchors.leftMargin: 10 * root.s
                    anchors.right: appRow.editing ? trashGlyph.left : ret.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1 * root.s

                    Item {
                        width: parent.width
                        height: nameText.implicitHeight

                        Text {
                            id: nameText
                            anchors.fill: parent
                            visible: !appRow.editing
                            text: appRow.entry ? appRow.entry.name : ""
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                            font.weight: appRow.selected ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        TextInput {
                            id: nameEdit
                            anchors.fill: parent
                            visible: appRow.editing
                            text: appRow.entry ? appRow.entry.name : ""
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 13 * root.s
                            selectByMouse: true
                            clip: true
                            onVisibleChanged: if (visible) {
                                selectAll();
                                forceActiveFocus();
                            }
                            onEditingFinished: {
                                var slug = root.appimageSlug(appRow.entry);
                                var nm = nameEdit.text.trim();
                                if (slug && nm.length > 0 && nm !== appRow.entry.name) {
                                    appimageProc.command = ["bash", root.appimageScript, "rename", slug, nm];
                                    appimageProc.running = true;
                                }
                                root.editIndex = -1;
                            }
                        }
                    }
                    Text {
                        id: sec
                        width: parent.width
                        visible: appRow.secondary.length > 0
                        text: appRow.secondary
                        color: appRow.selected ? Theme.dim : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    WheelScroller {
        anchors.fill: list
        s: root.s
        flick: list
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
