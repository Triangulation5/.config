import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.desktopwidgets
import qs.modules.settingsapp.config
import qs.modules.settingsapp.components

ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    property string searchText: ""

    readonly property bool materialEnabled: Store.adapter.style === "material"

    function widgetToggle(widget) {
        const widgetId = widget.id;
        return {
            key: "desktopWidget-" + widgetId,
            type: "toggle",
            label: widget.category + " · " + widget.label,
            caption: widget.description,
            get: function () { return DesktopWidgetState.isEnabled(widgetId); },
            set: function (value) { DesktopWidgetState.setEnabled(widgetId, value); }
        };
    }

    function rows() {
        var all = [];
        for (var i = 0; i < DesktopWidgetState.catalog.length; i++) {
            all.push(root.widgetToggle(DesktopWidgetState.catalog[i]));
        }
        all.push({
            key: "desktopWidget-clockStyle",
            type: "select",
            label: "Analog clock style",
            caption: "Choose the Nebula Bloom, Soft Organic, or Classic Circle face.",
            options: ["nebula", "organic", "circle"],
            names: ["Nebula Bloom", "Soft Organic", "Classic Circle"],
            get: function () { return DesktopWidgetState.clockStyle; },
            set: function (value) { DesktopWidgetState.setClockStyle(value); }
        });
        all.push({
            key: "desktopWidget-digitalClockStyle",
            type: "select",
            label: "Digital clock style",
            caption: "Choose the Veil, Bloom, Orbit, Script, Stack, Condensed, or Display face.",
            options: ["veil", "bloom", "orbit", "script", "stack", "condensed", "display"],
            names: ["Veil", "Bloom", "Orbit", "Script", "Stack", "Condensed", "Display"],
            get: function () { return DesktopWidgetState.digitalClockStyle; },
            set: function (value) { DesktopWidgetState.setDigitalClockStyle(value); }
        });
        all.push({
            key: "desktopWidget-musicStyle",
            type: "select",
            label: "Music widget style",
            caption: "Choose the ticket design or a minimal player with a live waveform.",
            options: ["ticket", "waveform"],
            names: ["Music Ticket", "Music + waveform"],
            get: function () { return DesktopWidgetState.musicStyle; },
            set: function (value) { DesktopWidgetState.setMusicStyle(value); }
        });
        all.push({
            key: "desktopWidgetNotes",
            type: "text",
            label: "Sticky note text",
            caption: "Text shown by the desktop Note widget.",
            placeholder: "Write a note",
            get: function () { return Store.adapter.desktopWidgetNotes; },
            set: function (value) { Store.set("desktopWidgetNotes", value); }
        });
        all.push({
            key: "desktopWidgetPhoto",
            type: "text",
            label: "Photo frame image path",
            caption: "Path to a local image file for the Photo Frame widget.",
            placeholder: "~/Pictures/photo.jpg",
            get: function () { return Store.adapter.desktopWidgetPhoto; },
            set: function (value) { Store.set("desktopWidgetPhoto", value); }
        });
        all.push({
            key: "desktopWidgetPomodoro",
            type: "action",
            label: "Pomodoro timer",
            caption: "Start or pause the focus timer shown by the Pomodoro widget.",
            button: DesktopWidgetState.focusTimerRunning ? "Pause" : "Start",
            done: "Done",
            action: function () { DesktopWidgetState.toggleFocusTimer(); }
        });
        all.push({
            key: "desktopWidgetPomodoroReset",
            type: "action",
            label: "Reset Pomodoro timer",
            caption: "Reset the focus timer to 25 minutes.",
            button: "Reset",
            done: "Reset",
            action: function () { DesktopWidgetState.resetFocusTimer(); }
        });
        var query = root.searchText.trim().toLowerCase();
        if (query.length === 0)
            return all;
        var filtered = [];
        for (var j = 0; j < all.length; j++) {
            var row = all[j];
            if ((row.label + " " + row.caption).toLowerCase().indexOf(query) >= 0)
                filtered.push(row);
        }
        return filtered;
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: intro.implicitHeight + 36
        radius: Theme.radiusCard
        color: Theme.card

        ColumnLayout {
            id: intro
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "Choose from 45 desktop widgets"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeNormal
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.materialEnabled
                    ? "Search the catalog below. Widgets appear only in Material style; arrange them freely, resize from a corner, and changes save as you go."
                    : "Desktop widgets are Material-only. Switch Design style to Material to show and arrange them."
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: editLabel.implicitWidth + 32
                    implicitHeight: 40
                    radius: Theme.radiusRow
                    color: root.materialEnabled ? Theme.accent : Theme.hover
                    opacity: root.materialEnabled ? 1 : 0.5

                    Text {
                        id: editLabel
                        anchors.centerIn: parent
                        text: "Arrange on desktop"
                        color: root.materialEnabled ? Theme.knob : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.materialEnabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: DesktopWidgetState.startEditing()
                    }
                }

                Rectangle {
                    implicitWidth: resetLabel.implicitWidth + 32
                    implicitHeight: 40
                    radius: Theme.radiusRow
                    color: Theme.hover

                    Text {
                        id: resetLabel
                        anchors.centerIn: parent
                        text: "Reset layout"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DesktopWidgetState.resetLayout()
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 52
        radius: Theme.radiusCard
        color: Theme.card

        TextField {
            anchors.fill: parent
            anchors.margins: 7
            text: root.searchText
            placeholderText: "Search desktop widgets"
            placeholderTextColor: Theme.textSecondary
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            selectByMouse: true

            background: Rectangle {
                radius: Theme.radiusRow
                color: Theme.searchField
                border.width: parent.activeFocus ? 1 : 0
                border.color: Qt.alpha(Theme.accent, 0.5)
            }

            onTextChanged: root.searchText = text
        }
    }

    SettingGroup {
        group: ({ card: "Widget catalog", rows: root.rows() })
    }

    Text {
        Layout.fillWidth: true
        visible: root.searchText.trim().length > 0 && root.rows().length === 0
        text: "No desktop widgets match “" + root.searchText.trim() + "”."
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: help.implicitHeight + 32
        radius: Theme.radiusCard
        color: Theme.card

        Text {
            id: help
            anchors.fill: parent
            anchors.margins: 16
            text: "In arrange mode, drag a widget to move it and use its lower-right handle to resize. Press Escape or Done to return. Your layout is shared across displays."
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }
    }
}
