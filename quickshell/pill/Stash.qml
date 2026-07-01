pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Singletons"
import "lib/fuzzy.js" as Fuzzy

/**
 * 蔵 STASH surface: the window classes that auto-route into the special:stash
 * space (SUPER+S), read from and written back to
 * ~/.config/hypr/modules/stash-apps.lua. Two views share one surface. The list
 * view shows each stashed class as an app tile, friendly name and faint raw-class
 * subtitle, with a ✕ to drop it, capped by a dashed "add app" bar. The add view
 * swaps in a fuzzy app search (the launcher's picker) whose pick derives a window
 * class from the entry's StartupWMClass, appends it and folds back to the list.
 *
 * Every add or remove regenerates the whole lua file through an atomic writer;
 * the write fires a debounced `hyprctl reload` so the new routing takes effect,
 * exactly as the keybinds editor reloads its binds.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    implicitHeight: content.implicitHeight

    signal requestSurface(string name)

    readonly property string stashPath: Quickshell.env("HOME") + "/.config/hypr/modules/stash-apps.lua"

    property var entries: []
    property bool addOpen: false
    property string query: ""
    property int selectedIndex: 0

    readonly property string header:
        "-- Window classes that auto-route into the special:stash space (SUPER+S).\n"
        + "-- The Settings rewrite this list, so keep it a plain array of strings.\n"

    /**
     * Collapse a window-class token to a comparable key: a two-char character
     * class like `[Ss]` keeps its lowercase letter, then everything non-alnum is
     * dropped so `[Ss]potify` and `Ghosttype-app` line up with an entry's
     * StartupWMClass or id.
     */
    function normalizeClass(cls) {
        return String(cls)
            .replace(/\[(.)(.)\]/g, "$2")
            .toLowerCase()
            .replace(/[^a-z0-9]/g, "");
    }

    readonly property var allApps: DesktopEntries.applications.values

    /**
     * The installed app behind a window class, used only to dress the row with a
     * real name and icon. Normalized equality on StartupWMClass, id or name is
     * preferred (Spotify: `[Ss]potify` → `spotify`); when nothing matches exactly,
     * a normalized substring link is tried (GhostType ships StartupWMClass
     * `GhostType` while its window class is `Ghosttype-app`, so `ghosttypeapp`
     * contains `ghosttype`). Among substring links the longest matched field wins,
     * so `ghosttypeapp` resolves to GhostType (`ghosttype`) and not Ghostty
     * (`ghostty`), and the substring side must be at least four chars so short
     * tokens cannot cross-link unrelated apps. Null when nothing matches.
     */
    function resolveEntry(cls) {
        var want = root.normalizeClass(cls);
        if (want.length === 0)
            return null;
        var apps = root.allApps;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (!e)
                continue;
            var cands = [e.startupClass, e.id, e.name];
            for (var j = 0; j < cands.length; j++)
                if (cands[j] && root.normalizeClass(cands[j]) === want)
                    return e;
        }
        var best = null;
        var bestLen = 0;
        for (var k = 0; k < apps.length; k++) {
            var e2 = apps[k];
            if (!e2)
                continue;
            var cands2 = [e2.startupClass, e2.id, e2.name];
            for (var n = 0; n < cands2.length; n++) {
                if (!cands2[n])
                    continue;
                var got = root.normalizeClass(cands2[n]);
                if (got.length < 4)
                    continue;
                var hit = (want.length >= 4 && got.indexOf(want) !== -1) || want.indexOf(got) !== -1;
                if (hit && got.length > bestLen) {
                    best = e2;
                    bestLen = got.length;
                }
            }
        }
        return best;
    }

    function parse(text) {
        var ri = text.indexOf("return {");
        var body = ri >= 0 ? text.slice(ri + 8) : text;
        var out = [];
        var re = /"([^"]*)"/g;
        var m;
        while ((m = re.exec(body)) !== null)
            if (m[1].length > 0)
                out.push(m[1]);
        return out;
    }

    function refresh() {
        root.entries = root.parse(stashFile.text());
    }

    function fileText(arr) {
        var body = "return {\n";
        for (var i = 0; i < arr.length; i++)
            body += "\t\"" + arr[i] + "\",\n";
        body += "}\n";
        return root.header + body;
    }

    function commit(arr) {
        writer.setText(root.fileText(arr));
    }

    function removeAt(i) {
        if (i < 0 || i >= root.entries.length)
            return;
        var next = root.entries.slice();
        next.splice(i, 1);
        root.commit(next);
    }

    function addClass(cls) {
        if (!cls || cls.length === 0)
            return;
        var want = root.normalizeClass(cls);
        for (var i = 0; i < root.entries.length; i++)
            if (root.normalizeClass(root.entries[i]) === want) {
                root.closeAdd();
                return;
            }
        var next = root.entries.slice();
        next.push(cls);
        root.commit(next);
        root.closeAdd();
    }

    function openAdd() {
        root.query = "";
        root.selectedIndex = 0;
        root.addOpen = true;
    }

    function closeAdd() {
        root.addOpen = false;
        root.query = "";
    }

    readonly property var allEntries: {
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && !src[i].noDisplay)
                out.push(src[i]);
        return out;
    }
    readonly property var results: Fuzzy.rank(allEntries, query, ({}))

    function pick() {
        if (results.length === 0 || selectedIndex < 0 || selectedIndex >= results.length)
            return;
        var e = results[selectedIndex];
        if (e)
            root.addClass(e.startupClass || e.id);
    }

    function move(delta) {
        if (results.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        addList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    onActiveChanged: {
        if (active) {
            stashFile.reload();
            refresh();
            addOpen = false;
            query = "";
        } else {
            addOpen = false;
            query = "";
        }
    }
    onResultsChanged: if (selectedIndex >= results.length) selectedIndex = 0;
    onAddOpenChanged: if (addOpen) Qt.callLater(search.input.forceActiveFocus)

    ameForm: "off"

    FileView {
        id: stashFile
        path: root.stashPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.refresh()
        onFileChanged: reload()
    }

    FileView {
        id: writer
        path: root.stashPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            reloadProc.running = true;
            stashFile.reload();
            root.refresh();
        }
        onSaveFailed: (err) => console.log("stash: write failed: " + err)
    }

    Process {
        id: reloadProc
        command: ["setsid", "-f", "sh", "-c", "sleep 0.4; hyprctl reload"]
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            width: parent.width
            height: 22 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "蔵"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "STASH"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
            }

            GlyphIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-left"
                color: Theme.iconDim
                stroke: 2.2
            }
        }

        Item { width: 1; height: 9 * root.s }

        /** ── list view ── */

        Item {
            width: parent.width
            height: visible ? 26 * root.s : 0
            visible: !root.addOpen && root.entries.length === 0

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: "No apps stashed yet"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
            }
        }

        ListView {
            id: list
            width: parent.width
            height: visible ? Math.min(contentHeight, 230 * root.s) : 0
            visible: !root.addOpen && root.entries.length > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.entries

            delegate: Item {
                id: erow
                required property int index
                required property string modelData

                readonly property var resolved: {
                    void root.allApps;
                    return root.resolveEntry(modelData);
                }
                readonly property string title: resolved && resolved.name ? resolved.name : modelData
                readonly property bool named: resolved && resolved.name && resolved.name !== modelData

                width: ListView.view.width
                height: 46 * root.s

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3 * root.s
                    anchors.bottomMargin: 3 * root.s
                    radius: 10 * root.s
                    color: rowHover.hovered ? Theme.frameBg : "transparent"
                    border.width: 1
                    border.color: rowHover.hovered ? Theme.frameBorder : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                HoverHandler { id: rowHover }

                Rectangle {
                    id: tile
                    anchors.left: parent.left
                    anchors.leftMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28 * root.s
                    height: 28 * root.s
                    radius: 7 * root.s
                    color: Theme.tileBg
                    border.width: 1
                    border.color: Theme.hairSoft

                    Text {
                        anchors.centerIn: parent
                        visible: !(icon.status === Image.Ready && icon.source != "")
                        text: erow.title.length > 0 ? erow.title.charAt(0).toUpperCase() : "?"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.weight: Font.DemiBold
                    }

                    Image {
                        id: icon
                        anchors.fill: parent
                        anchors.margins: 4 * root.s
                        sourceSize.width: Math.round(40 * root.s)
                        sourceSize.height: Math.round(40 * root.s)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: status === Image.Ready && source != ""
                        source: erow.resolved && erow.resolved.icon ? Quickshell.iconPath(erow.resolved.icon, true) : ""
                    }
                }

                Column {
                    anchors.left: tile.right
                    anchors.leftMargin: 12 * root.s
                    anchors.right: removeBtn.left
                    anchors.rightMargin: 10 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s

                    Text {
                        width: parent.width
                        text: erow.title
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: erow.named
                        text: erow.modelData
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.Normal
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: removeBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26 * root.s
                    height: 26 * root.s
                    radius: 7 * root.s
                    color: removeArea.containsMouse ? Qt.alpha(Theme.verm, 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "close"
                        color: removeArea.containsMouse ? Theme.vermLit : Theme.iconDim
                        stroke: 2
                    }

                    MouseArea {
                        id: removeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeAt(erow.index)
                    }
                }
            }
        }

        Item { width: 1; height: visible ? 6 * root.s : 0; visible: !root.addOpen }

        Item {
            width: parent.width
            height: visible ? 40 * root.s : 0
            visible: !root.addOpen

            Canvas {
                id: dash
                anchors.fill: parent
                anchors.topMargin: 4 * root.s
                anchors.bottomMargin: 4 * root.s
                property color stroke: Qt.alpha(Theme.vermLit, addArea.containsMouse ? 0.7 : 0.36)
                onStrokeChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var r = 9 * root.s;
                    var w = width;
                    var h = height;
                    var p = 0.5;
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = stroke;
                    ctx.setLineDash([4 * root.s, 4 * root.s]);
                    ctx.beginPath();
                    ctx.moveTo(p + r, p);
                    ctx.lineTo(w - p - r, p);
                    ctx.arcTo(w - p, p, w - p, p + r, r);
                    ctx.lineTo(w - p, h - p - r);
                    ctx.arcTo(w - p, h - p, w - p - r, h - p, r);
                    ctx.lineTo(p + r, h - p);
                    ctx.arcTo(p, h - p, p, h - p - r, r);
                    ctx.lineTo(p, p + r);
                    ctx.arcTo(p, p, p + r, p, r);
                    ctx.stroke();
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 6 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 14 * root.s
                    font.weight: Font.Bold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add app"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5 * root.s
                }
            }

            MouseArea {
                id: addArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openAdd()
            }
        }

        /** ── add view ── */

        Item {
            width: parent.width
            height: visible ? 22 * root.s : 0
            visible: root.addOpen

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * root.s

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * root.s
                    height: 16 * root.s

                    GlyphIcon {
                        anchors.fill: parent
                        name: "chevron-left"
                        color: addBackArea.containsMouse ? Theme.cream : Theme.iconDim
                        stroke: 1.8
                    }

                    MouseArea {
                        id: addBackArea
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeAdd()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ADD APP"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.4 * root.s
                }
            }
        }

        Item { width: 1; height: visible ? 4 * root.s : 0; visible: root.addOpen }

        SearchField {
            id: search
            width: parent.width
            visible: root.addOpen
            s: root.s
            kanji: "探"
            placeholder: "Search apps"
            counterText: root.results.length + ""
            onTextChanged: {
                root.query = text;
                root.selectedIndex = 0;
            }
            onMoved: (d) => root.move(d)
            onAccepted: root.pick()
            onDismissed: root.closeAdd()
        }

        Item { width: 1; height: visible ? 6 * root.s : 0; visible: root.addOpen }

        ListView {
            id: addList
            width: parent.width
            height: visible ? Math.min(contentHeight, 226 * root.s) : 0
            visible: root.addOpen
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 4 * root.s
            model: root.results.length

            delegate: Item {
                id: appRow
                required property int index
                width: addList.width
                height: 40 * root.s

                readonly property var entry: root.results[index]
                readonly property bool selected: index === root.selectedIndex

                Rectangle {
                    anchors.fill: parent
                    radius: 9 * root.s
                    visible: appRow.selected || appArea.containsMouse
                    color: appRow.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
                    border.width: appRow.selected ? 1 : 0
                    border.color: Theme.frameBorder
                }

                MouseArea {
                    id: appArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.selectedIndex = appRow.index
                    onClicked: {
                        root.selectedIndex = appRow.index;
                        root.pick();
                    }
                }

                Rectangle {
                    id: appTileBg
                    anchors.left: parent.left
                    anchors.leftMargin: 11 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: 6 * root.s
                    color: Qt.rgba(1, 1, 1, 0.05)
                    visible: !(appIcon.status === Image.Ready && appIcon.source != "")
                }
                Image {
                    id: appIcon
                    anchors.fill: appTileBg
                    sourceSize.width: Math.round(40 * root.s)
                    sourceSize.height: Math.round(40 * root.s)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready && source != ""
                    source: appRow.entry && appRow.entry.icon ? Quickshell.iconPath(appRow.entry.icon, true) : ""
                }

                Text {
                    anchors.left: appTileBg.right
                    anchors.leftMargin: 11 * root.s
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: appRow.entry ? appRow.entry.name : ""
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12.5 * root.s
                    font.weight: appRow.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
            }
        }

        Item { width: 1; height: 4 * root.s }
    }
}
