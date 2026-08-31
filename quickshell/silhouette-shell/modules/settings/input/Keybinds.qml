pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../utils/keybinds/binds.js" as Binds
import "../../../utils/keybinds/keychord.js" as Chord
import qs.services
import qs.modules.settings
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.layout

/**
 * 鍵 KEYBINDS surface: a searchable list of the keyboard shortcuts parsed from
 * ~/.config/hypr/modules/binds.lua, each row a combo chip on the left and its
 * name or derived action on the right; hovering a row reveals the underlying
 * command. Tapping a row opens a unified form prefilled in EDIT mode — a
 * key-binding field that arms chord capture, a name field and a command field
 * — with Save and Delete. A dashed bar at the bottom opens the same form EMPTY
 * in ADD mode. Save folds the minimal set of binds.js calls (rebind / editCmd /
 * editName, or add) into one text and writes it; the write reloads Hyprland and
 * re-parses. A command is only editable when it is a single string literal
 * (`exec_cmd("...")`); a non-exec dispatch or an env-prefixed exec path is shown
 * read-only as the raw action so it can never be clobbered.
 *
 * The capture path mirrors the wallpaper strip's search handoff: while
 * `listening`, an Item with focus swallows every keystroke; the captured combo
 * is held in form state and only applied on Save, so a mistaken chord can be
 * retried without touching the file.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    implicitHeight: content.implicitHeight

    signal requestSurface(string name)
    property alias bindList: list

    readonly property string bindsPath: Quickshell.env("HOME") + "/.config/hypr/modules/binds.lua"

    property var binds: []
    property int focusIndex: 0
    property bool listening: false
    property string conflict: ""

    property string query: ""

    property bool formOpen: false
    property bool formAdd: false
    property int formLine: -1
    property bool formCmdEditable: true
    property string formAction: ""
    property string formCombo: ""
    property string formName: ""
    property string formCmd: ""
    property string origCombo: ""
    property string origName: ""
    property string origCmd: ""
    property string origAction: ""

    /**
     * Binds whose combo, label, name or inner command contains the current query
     * as a case-insensitive substring. An empty query passes every bind through.
     */
    readonly property var filtered: {
        if (root.query.length === 0)
            return root.binds;
        var q = root.query.toLowerCase();
        return root.binds.filter(function (b) {
            return (b.combo + " " + b.label + " " + b.name + " " + b.cmd).toLowerCase().indexOf(q) !== -1;
        });
    }

    /**
     * Display form of a combo: mouse tokens are spelled out so a scroll or button
     * gesture reads clearly. These binds are shown read-only.
     */
    function comboPretty(c) {
        return c.replace("mouse_up", "Scroll ↑")
                .replace("mouse_down", "Scroll ↓")
                .replace("mouse:272", "LMB")
                .replace("mouse:273", "RMB");
    }

    function refresh() {
        root.binds = Binds.parse(bindsFile.text());
        if (root.focusIndex > root.filtered.length)
            root.focusIndex = Math.max(0, root.filtered.length);
    }

    /**
     * Focus the search field for a forward-slash keypress. With the form open
     * there is no search bar, so the slash lands in the form's name field
     * instead; while a chord capture is live the catcher owns the keys.
     */
    function focusSearch() {
        if (root.formOpen) {
            form.focusName();
            return;
        }
        if (root.listening)
            return;
        searchField.forceActiveFocus();
    }

    /**
     * Slide the focused row by `dir` (+1 down, -1 up), clamped over the filtered
     * list, and keep it in view. No-op while a chord capture is live so the arrow
     * keys feed the catcher instead.
     */
    function move(dir) {
        if (root.listening || root.formOpen)
            return;
        /** `filtered.length` is the dashed add bar, so focus can reach it. */
        root.focusIndex = Math.max(0, Math.min(root.filtered.length, root.focusIndex + dir));
        if (root.filtered.length > 0)
            list.positionViewAtIndex(Math.min(root.focusIndex, root.filtered.length - 1), ListView.Contain);
    }

    /**
     * Open the unified form in EDIT mode for the focused row, seeding form state
     * from the bind so Save can diff against the originals.
     */
    function activate() {
        if (root.listening)
            return;
        /** The dashed bar is the last focusable row: Enter on it adds a bind. */
        if (root.focusIndex >= root.filtered.length) {
            root.openAdd();
            return;
        }
        if (root.focusIndex < 0 || root.focusIndex >= root.filtered.length)
            return;
        openEdit(root.filtered[root.focusIndex]);
    }

    function openEdit(b) {
        if (b.isMouse)
            return;
        root.conflict = "";
        root.formAdd = false;
        root.formLine = b.lineIndex;
        root.formCmdEditable = b.isExec && b.cmd.length > 0;
        root.formAction = b.action;
        root.formCombo = b.combo;
        root.formName = b.name;
        root.formCmd = b.cmd;
        root.origCombo = b.combo;
        root.origName = b.name;
        root.origCmd = b.cmd;
        root.origAction = b.action;
        root.formOpen = true;
    }

    function openAdd() {
        root.conflict = "";
        root.listening = false;
        root.formAdd = true;
        root.formLine = -1;
        root.formCmdEditable = true;
        root.formAction = "";
        root.formCombo = "";
        root.formName = "";
        root.formCmd = "";
        root.origCombo = "";
        root.origName = "";
        root.origCmd = "";
        root.origAction = "";
        root.formOpen = true;
    }

    function closeForm() {
        root.formOpen = false;
        root.listening = false;
        root.conflict = "";
    }

    /**
     * Apply a captured chord to the form state (not the file). A bare modifier is
     * ignored so capture keeps waiting for the final key; Escape ends capture.
     */
    function capture(key, modifiers) {
        if (key === Qt.Key_Escape) {
            root.listening = false;
            return;
        }
        var combo = Chord.chord(key, modifiers);
        if (combo === null)
            return;
        root.formCombo = combo;
        root.conflict = "";
        root.listening = false;
        Qt.callLater(form.focusName);
    }

    /**
     * Commit the form. ADD guards the combo against an existing bind, then writes
     * one appended exec line. EDIT folds only the changed facets — combo via
     * rebind, command via editCmd, name via editName — into a single text before
     * one write. A combo that collides with another bind is refused inline.
     */
    function save() {
        var text = bindsFile.text();
        if (root.formAdd) {
            if (root.formCombo.length === 0) { root.conflict = "pick a key"; return; }
            if (root.formCmd.length === 0) { root.conflict = "command empty"; return; }
            if (Binds.inUse(text, root.formCombo, -1)) {
                root.conflict = root.formCombo + " already bound";
                return;
            }
            var a = Binds.add(text, root.formCombo, root.formCmd, root.formName);
            if (!a.ok) { root.conflict = a.error || "add failed"; return; }
            writer.setText(a.text);
            return;
        }

        if (root.formCombo !== root.origCombo && Binds.inUse(text, root.formCombo, root.formLine)) {
            root.conflict = root.formCombo + " already bound";
            return;
        }

        var out = text;
        if (root.formCombo !== root.origCombo) {
            var r = Binds.rebind(out, root.formLine, root.formCombo);
            if (!r.ok) { root.conflict = r.error || "rebind failed"; return; }
            out = r.text;
        }
        if (root.formCmdEditable && root.formCmd !== root.origCmd) {
            if (root.formCmd.length === 0) { root.conflict = "command empty"; return; }
            var c = Binds.editCmd(out, root.formLine, root.formCmd);
            if (!c.ok) { root.conflict = c.error || "command edit failed"; return; }
            out = c.text;
        }
        if (!root.formCmdEditable && root.formAction !== root.origAction) {
            if (root.formAction.trim().length === 0) { root.conflict = "action empty"; return; }
            var a2 = Binds.editAction(out, root.formLine, root.formAction.trim());
            if (!a2.ok) { root.conflict = a2.error || "action edit failed"; return; }
            out = a2.text;
        }
        if (root.formName !== root.origName) {
            var n = Binds.editName(out, root.formLine, root.formName);
            if (!n.ok) { root.conflict = n.error || "name edit failed"; return; }
            out = n.text;
        }

        if (out === text) {
            closeForm();
            return;
        }
        writer.setText(out);
    }

    function removeBind() {
        if (root.formAdd || root.formLine < 0)
            return;
        var d = Binds.del(bindsFile.text(), root.formLine);
        if (!d.ok) { root.conflict = d.error || "delete failed"; return; }
        writer.setText(d.text);
    }

    onActiveChanged: {
        if (active) {
            bindsFile.reload();
            refresh();
            focusIndex = 0;
            listening = false;
            query = "";
            formOpen = false;
            conflict = "";
        } else {
            listening = false;
            formOpen = false;
            conflict = "";
        }
    }

    onFormOpenChanged: if (formOpen) Qt.callLater(form.focusName)

    readonly property Item focusRowItem: list.focusRowItem

    readonly property bool rowFocused: focusRowItem !== null && active && !formOpen

    readonly property point rowPoint: {
        void root.width;
        void root.height;
        void root.focusIndex;
        void list.contentY;
        if (!focusRowItem)
            return Qt.point(4 * root.s, root.height / 2);
        return focusRowItem.mapToItem(root, 4 * root.s, focusRowItem.height / 2);
    }

    ameForm: rowFocused ? "rowseam" : "off"
    amePoint: rowPoint

    FileView {
        id: bindsFile
        path: root.bindsPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.refresh()
        onFileChanged: reload()
    }

    FileView {
        id: writer
        path: root.bindsPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            reloadProc.running = true;
            root.formOpen = false;
            root.listening = false;
            root.conflict = "";
            bindsFile.reload();
            root.refresh();
        }
        onSaveFailed: (err) => {
            root.conflict = "write failed";
            console.log("keybinds: write failed: " + err);
        }
    }

    Process {
        id: reloadProc
        command: ["setsid", "-f", "sh", "-c", "sleep 0.4; hyprctl reload"]
    }

    Item {
        id: keyCatcher
        focus: root.listening
        Keys.onPressed: (e) => {
            if (!root.listening)
                return;
            e.accepted = true;
            root.capture(e.key, e.modifiers);
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SurfaceHeader {
            s: root.s
            kanji: "鍵"
            label: "KEYBINDS"
            showBack: true
        }

        Item { width: 1; height: 8 * root.s }

        KeybindSearch {
            s: root.s
            host: root
        }

        Item { width: 1; height: 8 * root.s }

        ListView {
            id: list
            width: parent.width
            height: visible ? Math.min(contentHeight, 250 * root.s) : 0
            visible: !root.formOpen
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.filtered

            property Item focusRowItem: null

            delegate: KeybindRow {
                required property int index
                required property var modelData
                surface: root
                s: root.s
                rowIndex: index
                kbCombo: modelData.combo
                kbLabel: modelData.label
                kbCmd: modelData.cmd
                kbIsMouse: modelData.isMouse
            }
        }

        KeybindAddBar {
            s: root.s
            host: root
            focused: root.focusIndex === root.filtered.length
        }

        KeybindForm {
            id: form
            width: parent.width
            visible: root.formOpen
            surface: root
        }

        Item { width: 1; height: 9 * root.s }

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
                text: root.formOpen ? "↵ save · esc back" : "↑↓ move · ↵ edit · + add · / search · esc close"
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

