pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import qs.components.icons
import qs.modules.settings
import qs.modules.quicksettings
import "../../utils/quicksettings/registry.js" as Registry

/**
 * The standalone settings window's body: a self-contained card that lists
 * every shell setting from the registry ([[Registry]]) — nothing here knows
 * about the pill, the morph or any surface host. A search bar filters the
 * whole index live (label, caption and alias terms, multi-token), and with an
 * empty query the rows browse grouped under their section captions. Every
 * editor binds straight to Flags, so a change persists exactly like the older
 * category surfaces commit theirs. The window root (SettingsRoot.qml) owns
 * show/hide, monitor placement and the IPC surface.
 */
Item {
    id: root

    /** Scale, matching the shell's per-screen convention. */
    readonly property real s: (Quickshell.screens.length > 0 ? (Quickshell.screens[0].height / 1080) * Flags.uiScale : 1)

    property string query: ""

    /** Emitted when Escape reaches the panel with nothing else consuming it. */
    signal requestClose()

    /** Index into `rows` of the focused row, -1 while the search field owns the keys. */
    property int kbIndex: -1

    /** Rows currently focusable, in display order: the loaded QsRow delegates. */
    property var rows: []

    readonly property bool searching: query.trim().length > 0

    /**
     * Display entries. Browsing walks the registry grouped in order; searching
     * flattens the scored matches. Headers are decorative and skip focus.
     */
    readonly property var entries: {
        var out = [];
        if (root.searching) {
            var hits = Registry.search(root.query);
            for (var h = 0; h < hits.length; h++)
                out.push({ kind: "row", row: hits[h].row });
            return out;
        }
        var groups = Registry.groupOrder;
        for (var g = 0; g < groups.length; g++) {
            var rowsOf = Registry.byGroup(groups[g]);
            if (rowsOf.length === 0)
                continue;
            out.push({ kind: "header", label: groups[g] });
            for (var r = 0; r < rowsOf.length; r++)
                out.push({ kind: "row", row: rowsOf[r] });
        }
        return out;
    }

    onEntriesChanged: Qt.callLater(root.resync)
    onKbIndexChanged: {
        rowHost.focusRowItem = (kbIndex >= 0 && kbIndex < rows.length) ? rows[kbIndex].item : null;
        if (kbIndex >= 0 && kbIndex < rows.length)
            list.ensureVisible(rows[kbIndex].item);
    }

    /**
     * The row-host object the QsRows see as their `surface`: it serves the
     * scale, the keyboard-focus item and the hover/click callbacks of the
     * SettingsSurface protocol, so the shared row components run unmodified
     * inside a plain window.
     */
    QtObject {
        id: rowHost
        readonly property real s: root.s
        property Item focusRowItem: null
        function reportRowHover(item, hovered) { root.reportRowHover(item, hovered); }
        function activateRow(item) { root.activateRow(item); }
    }

    /** Rebuild the focusable-rows list from the delegates that exist now. */
    function resync() {
        var out = [];
        for (var i = 0; i < entryRepeater.count; i++) {
            var it = entryRepeater.itemAt(i);
            if (it && it.item && it.item.row !== undefined)
                out.push({ item: it.item });
        }
        root.rows = out;
        if (root.kbIndex >= out.length)
            root.kbIndex = out.length - 1;
        rowHost.focusRowItem = (root.kbIndex >= 0 && root.kbIndex < out.length) ? out[root.kbIndex].item : null;
    }

    /** Step the focused row by `dir` and keep it in view. */
    function kbMove(dir) {
        if (rows.length === 0)
            return;
        kbIndex = Math.max(0, Math.min(rows.length - 1, (kbIndex < 0 ? 0 : kbIndex + dir)));
    }

    /** Adjust the focused row: bump handles toggle/seg/int uniformly. */
    function kbAdjust(dir) {
        if (rows.length === 0)
            return;
        if (kbIndex < 0)
            kbIndex = 0;
        var it = rows[kbIndex].item;
        if (it.bump)
            it.bump(dir);
        else if (it.activate)
            it.activate();
    }

    /** Return on the focused row: toggle flips, text opens its field. */
    function kbActivate() {
        if (kbIndex < 0 || kbIndex >= rows.length)
            return;
        var it = rows[kbIndex].item;
        if (it.activate)
            it.activate();
    }

    /** Route a printable key into the search field (the `/` affordance). */
    function focusSearch() {
        search.focusField();
    }

    /** Escape at the panel level (no field focused): ask the window to close. */
    Keys.onEscapePressed: root.requestClose()

    /** Clear search + focus on every open, so the panel opens fresh. */
    function reset() {
        query = "";
        kbIndex = -1;
        search.clear();
    }

    /** Hover sync: the highlighted row follows the pointer, mouse and keys agree. */
    function reportRowHover(item, hovered) {
        if (!hovered)
            return;
        for (var i = 0; i < rows.length; i++)
            if (rows[i].item === item) {
                kbIndex = i;
                break;
            }
    }

    /** Click on a row: focus it and run its activate (toggle flip / text edit). */
    function activateRow(item) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].item === item) {
                kbIndex = i;
                if (item.activate)
                    item.activate();
                return;
            }
    }

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        radius: 22 * root.s
        border.width: 1
        border.color: Theme.border
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.cardTop }
            GradientStop { position: 1.0; color: Theme.cardBot }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
            shadowBlur: 0.75
            shadowVerticalOffset: 4 * root.s
        }

        implicitWidth: 420 * root.s
        implicitHeight: 16 * root.s + headerCol.implicitHeight + 14 * root.s

        Column {
            id: headerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 16 * root.s
            anchors.leftMargin: 20 * root.s
            anchors.rightMargin: 20 * root.s
            spacing: 0

            Row {
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "設"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SETTINGS"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }

                Item { width: 1; height: 1 }

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * root.s
                    height: 16 * root.s
                    name: "cog"
                    color: Theme.iconDim
                    stroke: 1.7
                }
            }

            Item { width: 1; height: 10 * root.s }

            QsSearch {
                id: search
                host: root
            }

            Item { width: 1; height: 8 * root.s }

            Flickable {
                id: list

                /** Keep the focused row on screen while arrowing through. */
                function ensureVisible(item) {
                    if (!item)
                        return;
                    var y = item.mapToItem(list, 0, 0).y;
                    if (y < 0)
                        list.contentY = Math.max(0, list.contentY + y);
                    else if (y + item.height > list.height)
                        list.contentY = Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + y + item.height - list.height);
                }

                width: parent.width
                height: Math.min(contentHeight, 520 * root.s)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: entriesCol.implicitHeight
                interactive: contentHeight > height

                Column {
                    id: entriesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    Repeater {
                        id: entryRepeater

                        model: root.entries

                        delegate: Loader {
                            id: entryLoader

                            required property int index
                            required property var modelData

                            width: parent.width
                            /** Loaders of plain Items don't auto-size; drive it so the Column stacks. */
                            height: entryLoader.item ? entryLoader.item.height : 0
                            sourceComponent: entryLoader.modelData.kind === "header" ? headerComp : rowComp
                            onItemChanged: Qt.callLater(root.resync)

                            Component {
                                id: headerComp

                                Text {
                                    topPadding: 12 * root.s
                                    bottomPadding: 3 * root.s
                                    leftPadding: 12 * root.s
                                    text: entryLoader.modelData.label
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 8.5 * root.s
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1.2 * root.s
                                }
                            }

                            Component {
                                id: rowComp

                                QsRow {
                                    surface: rowHost
                                    row: entryLoader.modelData.row
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 6 * root.s }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairSoft
            }

            Item {
                width: parent.width
                height: 20 * root.s

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 4 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.searching
                        ? root.entries.length + " results · esc clears"
                        : "↑↓ move · ←→ adjust · ↵ edit · / search · esc close"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllLowercase
                    font.letterSpacing: 1 * root.s
                }
            }
        }
    }
}
