import QtQuick
import QtQuick.Layouts
import qs.modules.desktopwidgets
import qs.modules.settingsapp.config
import qs.modules.settingsapp.components

ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    readonly property bool materialEnabled: Store.adapter.style === "material"

    function rows() {
        var result = [];
        for (var i = 0; i < DesktopWidgetState.catalog.length; i++) {
            const widgetId = DesktopWidgetState.catalog[i].id;
            const widget = DesktopWidgetState.catalog[i];
            result.push({
                key: "desktopWidget-" + widgetId,
                type: "toggle",
                label: widget.label,
                caption: widget.description,
                get: function () { return DesktopWidgetState.isEnabled(widgetId); },
                set: function (value) { DesktopWidgetState.setEnabled(widgetId, value); }
            });
        }
        result.push({
            key: "desktopWidget-musicStyle",
            type: "select",
            label: "Music widget style",
            caption: "Choose the ticket design or a minimal player with a live squiggle.",
            options: ["ticket", "line"],
            names: ["Music Ticket", "Music + squiggle"],
            get: function () { return DesktopWidgetState.musicStyle; },
            set: function (value) { DesktopWidgetState.setMusicStyle(value); }
        });
        return result;
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
                text: "Choose your desktop widgets"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeNormal
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.materialEnabled
                    ? "Widgets are shown on the desktop only in Material style. Arrange them freely, resize from a corner, and changes save as you go."
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

    SettingGroup {
        group: ({ card: "Available widgets", rows: root.rows() })
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
