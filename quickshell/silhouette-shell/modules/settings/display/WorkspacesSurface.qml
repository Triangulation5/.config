pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../../../utils/keybinds/keychord.js" as Chord
import qs.services
import qs.modules.settings
import qs.modules.pill.widgets
import qs.modules.pill.surfaces
import qs.components.icons
import qs.components.layout

/**
 * 場 WORKSPACES hub: a glance at Hyprland's special spaces and the keys that
 * summon them. The three built-in rows (Stash, Private, Minimized) sit on top;
 * below them every user-defined space from the Spaces store gets its own row with
 * a Super+<key> chip, a chevron into its app manager (SpaceApps) and a remove
 * control on hover. A dashed "Add Workspace" bar at the bottom swaps the surface
 * into a create form — name, description and a captured single-letter key — that
 * makes a new space on confirm.
 *
 * Built on the plain surface base like Stash and Keybinds; the host routes its
 * header-back to the settings index (or, while the form is open, back to the
 * list) and each navigable row's tap to the matching surface.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    implicitHeight: content.implicitHeight

    signal requestSurface(string name)

    ameForm: "off"

    property bool formOpen: false
    property bool listening: false
    property string conflict: ""
    property string formName: ""
    property string formDesc: ""
    property string formKey: ""

    readonly property var spaces: [
        { name: "Stash", key: "Super + S", note: "Background apps that open here", surface: "stash" },
        { name: "Private", key: "Super + P", note: "Hidden scratchpad", surface: "" },
        { name: "Minimized", key: "Super + Shift + M", note: "Minimized windows", surface: "" }
    ]

    /**
     * Keyboard focus covers only actionable rows: the Stash nav row (index 0),
     * then one row per user space, then the dashed add bar as the final row.
     * The dead Private/Minimized captions are skipped so Enter is never a
     * no-op.
     */
    property int focusIndex: 0
    readonly property int rowCount: 1 + Spaces.list.length + 1

    /** Slide the focused row by `dir` (+1 down, -1 up). No-op while the form is open. */
    function move(dir) {
        if (root.formOpen)
            return;
        root.focusIndex = Math.max(0, Math.min(root.rowCount - 1, root.focusIndex + dir));
    }

    /**
     * Enter on the focused row: the Stash row opens the stash, a user space
     * opens its app manager, and the add bar opens the create form.
     */
    function activate() {
        if (root.formOpen)
            return;
        if (root.focusIndex === 0) {
            root.requestSurface("stash");
        } else if (root.focusIndex < 1 + Spaces.list.length) {
            var sp = Spaces.list[root.focusIndex - 1];
            Spaces.editing = sp.id;
            root.requestSurface("spaceapps");
        } else {
            root.openForm();
        }
    }

    function openForm() {
        root.formName = "";
        root.formDesc = "";
        root.formKey = "";
        root.conflict = "";
        root.listening = false;
        root.formOpen = true;
    }

    function closeForm() {
        root.formOpen = false;
        root.listening = false;
        root.conflict = "";
    }

    /**
     * Fold a captured keypress into a single uppercase letter for the new space's
     * key. Modifiers are dropped (Super is auto-prefixed), a bare modifier keeps
     * capture waiting, Escape ends it, and anything that is not one A–Z letter is
     * refused inline.
     */
    function capture(key, modifiers) {
        if (key === Qt.Key_Escape) {
            root.listening = false;
            return;
        }
        var name = Chord.chord(key, 0);
        if (name === null)
            return;
        if (!/^[A-Z]$/.test(name)) {
            root.conflict = "single letter only";
            root.listening = false;
            return;
        }
        root.formKey = name;
        root.conflict = "";
        root.listening = false;
    }

    /**
     * Validate and create the space. Name must slug to a non-empty, unused id; the
     * key must be one letter and free of every existing bind. A clash is reported
     * inline so nothing is written until it is resolved.
     */
    function create() {
        var name = root.formName.trim();
        if (name.length === 0) { root.conflict = "name empty"; return; }
        var id = Spaces.slug(name);
        if (id.length === 0) { root.conflict = "name needs a letter"; return; }
        if (Spaces.reserved(id)) { root.conflict = name + " is reserved"; return; }
        for (var i = 0; i < Spaces.list.length; i++)
            if (Spaces.list[i].id === id) { root.conflict = name + " already exists"; return; }
        if (!/^[A-Za-z]$/.test(root.formKey)) { root.conflict = "pick a key"; return; }
        if (Spaces.keyTaken(root.formKey)) { root.conflict = "Super + " + root.formKey.toUpperCase() + " in use"; return; }
        Spaces.addSpace(name, root.formDesc.trim(), root.formKey.toUpperCase());
        root.closeForm();
    }

    onActiveChanged: {
        formOpen = false;
        listening = false;
        conflict = "";
        focusIndex = 0;
    }

    onFormOpenChanged: if (formOpen) Qt.callLater(nameField.forceActiveFocus)

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
            kanji: "場"
            label: "WORKSPACES"
            showBack: true
        }

        Item { width: 1; height: 8 * root.s }


        Column {
            id: listCol
            width: parent.width
            visible: !root.formOpen
            spacing: 0

            Repeater {
                model: root.spaces

                delegate: WorkspaceNavRow {
                    required property int index
                    required property var modelData
                    surface: root
                    s: root.s
                    wsName: modelData.name
                    wsNote: modelData.note
                    wsKey: modelData.key
                    wsNavSurface: modelData.surface
                }
            }

            Repeater {
                model: Spaces.list

                delegate: WorkspaceRuleRow {
                    required property int index
                    required property var modelData
                    surface: root
                    s: root.s
                    rowIndex: index
                    wsName: modelData.name
                    wsDesc: modelData.desc
                    wsKey: modelData.key
                    wsId: modelData.id
                }
            }

            Item { width: 1; height: 6 * root.s }

            Item {
                width: parent.width
                height: 40 * root.s

                Canvas {
                    id: dash
                    anchors.fill: parent
                    anchors.topMargin: 4 * root.s
                    anchors.bottomMargin: 4 * root.s
                    property color stroke: Qt.alpha(Theme.vermLit, (addArea.containsMouse || root.focusIndex === root.rowCount - 1) ? 0.7 : 0.36)

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
                        text: "Add Workspace"
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
                    onClicked: root.openForm()
                }
            }
        }

        WorkspaceForm {
            s: root.s
            host: root
        }

        Item { width: 1; height: 4 * root.s }
    }
}
