import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services
import qs.modules.settingsapp.components
import "../utils/keybinds/keychord.js" as Chord

/**
 * The Workspaces page body: the special workspaces, one row each, with the keys
 * they answer to and the window classes that route into them — plus a create form
 * that writes a new space into the store and a toggle for it into the binds.
 *
 * The rows are built here rather than declared as data because the list is the
 * user's: it grows, shrinks and carries per-row state (which row is unfolded, what
 * is half-typed in a field). It is the same shape as the shell's own Workspaces
 * and SpaceApps surfaces merged into one page, since a settings window has room
 * for the apps of a space under the space itself, and a second navigation level
 * for one text field is a level too many.
 *
 * A row for a space the user bound by hand is shown but not editable: it is in
 * `binds.lua` and nowhere else, so the page accounts for it and says so instead of
 * pretending it is ours to rewrite.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    /** The id of the space whose apps are unfolded, or "". */
    property string expandedId: ""

    /** The create form's state. Open is the form; listening is key capture. */
    property bool formOpen: false
    property bool listening: false
    property string formName: ""
    property string formDesc: ""
    property string formKey: ""
    property string conflict: ""

    readonly property var entries: Spaces.entries()

    /** Why the form cannot be submitted, or "". Shown as it is typed. */
    readonly property string formProblem: root.conflict.length > 0 ? root.conflict : Spaces.problem(root.formName, root.formKey)

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

    function create() {
        if (root.formProblem.length > 0)
            return;
        if (Spaces.addSpace(root.formName, root.formDesc, root.formKey))
            root.closeForm();
    }

    /**
     * Fold a captured keypress into a single letter for the new space. Modifiers
     * are dropped (Super is prefixed for us), a bare modifier keeps capture
     * waiting, Escape ends it, and anything that is not one A–Z letter is refused
     * inline — the same rule the shell's capture uses.
     */
    function capture(key) {
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

    // Key capture: it only takes focus while the form is listening, so the panel's
    // own keys are never swallowed by a field waiting for a letter.
    Item {
        id: catcher
        focus: root.listening
        Keys.onPressed: (event) => {
            if (!root.listening)
                return;
            event.accepted = true;
            root.capture(event.key);
        }
    }

    SectionLabel {
        Layout.fillWidth: true
        visible: !root.formOpen
        text: "Special spaces"
    }

    Rectangle {
        Layout.fillWidth: true
        visible: !root.formOpen
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: spaceColumn.implicitHeight + 36

        ColumnLayout {
            id: spaceColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 6

            Repeater {
                model: root.entries

                delegate: ColumnLayout {
                    id: entry

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 8

                    readonly property bool managed: entry.modelData.managed
                    readonly property bool expanded: root.expandedId === entry.modelData.id

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 42

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusRow
                            color: entryMouse.containsMouse ? Theme.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: entry.managed
                            cursorShape: entry.managed ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.expandedId = entry.expanded ? "" : entry.modelData.id
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.name
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeNormal
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: entry.managed
                                        ? (entry.modelData.desc.length > 0 ? entry.modelData.desc : "No description")
                                        : "Bound in binds.lua by hand"
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSection
                                    elide: Text.ElideRight
                                }
                            }

                            // The chord, in the shell's keychip shape.
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: keyLabel.implicitWidth + 16
                                implicitHeight: 22
                                radius: 7
                                color: Theme.searchField
                                border.width: 1
                                border.color: Theme.border

                                Text {
                                    id: keyLabel
                                    anchors.centerIn: parent
                                    text: entry.modelData.key.length > 0 ? entry.modelData.key : "unbound"
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSection
                                    font.bold: true
                                }
                            }

                            // Remove, for the spaces this page owns.
                            Item {
                                Layout.alignment: Qt.AlignVCenter
                                visible: entry.managed
                                implicitWidth: 22
                                implicitHeight: 22

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 7
                                    color: removeMouse.containsMouse ? Qt.alpha(Theme.accent, 0.16) : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u00D7"
                                        color: removeMouse.containsMouse ? Theme.accent : Theme.textSecondary
                                        font.pixelSize: 15
                                    }
                                }

                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.expandedId === entry.modelData.id)
                                            root.expandedId = "";
                                        Spaces.removeSpace(entry.modelData.id);
                                    }
                                }
                            }

                            // Unfold chevron.
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                visible: entry.managed
                                text: entry.expanded ? "\u25BE" : "\u25B8"
                                color: Theme.textSecondary
                                font.pixelSize: 12
                            }
                        }
                    }

                    // The apps that open straight into this space — the shell's
                    // app manager, under the space it belongs to.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.bottomMargin: 6
                        visible: entry.managed && entry.expanded
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            text: "Window classes that open here"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSection
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: entry.modelData.apps

                                delegate: Rectangle {
                                    id: chip

                                    required property var modelData

                                    implicitWidth: chipLabel.implicitWidth + chipRemove.width + 20
                                    implicitHeight: 24
                                    radius: 7
                                    color: Theme.searchField
                                    border.width: 1
                                    border.color: Theme.border

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            id: chipLabel
                                            text: chip.modelData
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSizeSection
                                        }

                                        Text {
                                            id: chipRemove
                                            text: "\u00D7"
                                            color: chipMouse.containsMouse ? Theme.accent : Theme.textSecondary
                                            font.pixelSize: 13

                                            MouseArea {
                                                id: chipMouse
                                                anchors.fill: parent
                                                anchors.margins: -3
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Spaces.removeApp(entry.modelData.id, chip.modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: entry.modelData.apps.length === 0
                                text: "Nothing yet"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSection
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 8
                                color: Theme.searchField
                                border.width: 1
                                border.color: appField.activeFocus ? Qt.alpha(Theme.accent, 0.35) : Theme.border

                                TextInput {
                                    id: appField
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSection
                                    selectByMouse: true
                                    clip: true

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "firefox"
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSection
                                        visible: appField.text.length === 0
                                    }

                                    // Enter adds and clears, so a list of classes
                                    // can be typed without reaching for the button.
                                    onAccepted: {
                                        Spaces.addApp(entry.modelData.id, text);
                                        text = "";
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: addLabel.implicitWidth + 22
                                implicitHeight: 28
                                radius: 8
                                color: addMouse.containsMouse ? Theme.hover : Theme.navButton

                                Text {
                                    id: addLabel
                                    anchors.centerIn: parent
                                    text: "Add"
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSection
                                    font.bold: true
                                }

                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Spaces.addApp(entry.modelData.id, appField.text);
                                        appField.text = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.entries.length === 0
                text: "No special workspaces. Add one below."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Item { Layout.preferredHeight: 4 }

            // The dashed "Add Workspace" bar, as the shell's hub has it.
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 38

                Canvas {
                    id: dashed
                    anchors.fill: parent
                    property color stroke: addArea.containsMouse ? Qt.alpha(Theme.accent, 0.7) : Qt.alpha(Theme.accent, 0.36)
                    onStrokeChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var r = 9;
                        var w = width;
                        var h = height;
                        var p = 0.5;
                        ctx.lineWidth = 1;
                        ctx.strokeStyle = stroke;
                        ctx.setLineDash([4, 4]);
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

                Text {
                    anchors.centerIn: parent
                    text: "+   Add Workspace"
                    color: Theme.accent
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
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
    }

    // Create form: replaces the list, the way the shell's hub does.
    Rectangle {
        Layout.fillWidth: true
        visible: root.formOpen
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: formColumn.implicitHeight + 36

        ColumnLayout {
            id: formColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            SectionLabel {
                Layout.fillWidth: true
                text: "New workspace"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "NAME"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSection
                    font.letterSpacing: 1
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 8
                    color: Theme.searchField
                    border.width: 1
                    border.color: nameField.activeFocus ? Qt.alpha(Theme.accent, 0.35) : Theme.border

                    TextInput {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeNormal
                        selectByMouse: true
                        onTextEdited: root.formName = text
                        Keys.onEscapePressed: root.closeForm()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Chat"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            visible: nameField.text.length === 0
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "DESCRIPTION"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSection
                    font.letterSpacing: 1
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 8
                    color: Theme.searchField
                    border.width: 1
                    border.color: descField.activeFocus ? Qt.alpha(Theme.accent, 0.35) : Theme.border

                    TextInput {
                        id: descField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeNormal
                        selectByMouse: true
                        onTextEdited: root.formDesc = text
                        Keys.onEscapePressed: root.closeForm()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Chat windows (optional)"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                            visible: descField.text.length === 0
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "KEY"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSection
                    font.letterSpacing: 1
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 8
                    color: root.listening ? Qt.alpha(Theme.accent, 0.12) : Theme.searchField
                    border.width: 1
                    border.color: root.listening ? Qt.alpha(Theme.accent, 0.55) : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.listening ? "press a letter\u2026  esc cancels"
                            : (root.formKey.length > 0 ? "Super + " + root.formKey : "tap to set a key")
                        color: root.listening || root.formKey.length > 0 ? Theme.text : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: root.formKey.length > 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.conflict = "";
                            root.listening = true;
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.formProblem.length > 0
                text: root.formProblem
                color: Theme.accent
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: cancelLabel.implicitWidth + 24
                    implicitHeight: 30
                    radius: 8
                    color: cancelMouse.containsMouse ? Theme.hover : "transparent"
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeNormal
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeForm()
                    }
                }

                Rectangle {
                    enabled: root.formProblem.length === 0
                    implicitWidth: createLabel.implicitWidth + 28
                    implicitHeight: 30
                    radius: 8
                    opacity: enabled ? 1 : 0.5
                    color: createMouse.containsMouse && enabled ? Theme.accent : Qt.alpha(Theme.accent, 0.85)

                    Text {
                        id: createLabel
                        anchors.centerIn: parent
                        text: "Create"
                        color: Theme.knob
                        font.pixelSize: Theme.fontSizeNormal
                        font.bold: true
                    }

                    MouseArea {
                        id: createMouse
                        anchors.fill: parent
                        enabled: root.formProblem.length === 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.create()
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
