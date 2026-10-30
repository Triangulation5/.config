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

    function widgetEnabled(widgetId) {
        var saved = Store.adapter.desktopWidgets;
        if (Array.isArray(saved)) {
            for (var i = 0; i < saved.length; i++)
                if (saved[i] && saved[i].id === widgetId)
                    return saved[i].enabled !== false;
        }
        return true;
    }

    function updateWidget(widgetId, patch) {
        var saved = Array.isArray(Store.adapter.desktopWidgets)
            ? Store.adapter.desktopWidgets : [];
        var next = [];
        for (var i = 0; i < DesktopWidgetState.catalog.length; i++) {
            var spec = DesktopWidgetState.catalog[i];
            var entry = null;
            for (var j = 0; j < saved.length; j++) {
                if (saved[j] && saved[j].id === spec.id) {
                    entry = saved[j];
                    break;
                }
            }
            var value = Object.assign({}, spec, entry || {});
            if (value.id === widgetId)
                Object.assign(value, patch);
            next.push({
                id: value.id,
                enabled: value.enabled !== false,
                x: value.x,
                y: value.y,
                w: value.w,
                h: value.h,
                musicStyle: value.musicStyle
            });
        }
        Store.set("desktopWidgets", next);
    }

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
                get: function () { return root.widgetEnabled(widgetId); },
                set: function (value) { root.updateWidget(widgetId, { enabled: value }); }
            });
        }
        result.push({
            key: "desktopWidget-musicStyle",
            type: "select",
            label: "Music widget style",
            caption: "Choose the ticket design or a minimal player with a live squiggle.",
            options: ["ticket", "line"],
            names: ["Music Ticket", "Music + squiggle"],
            get: function () {
                var saved = Store.adapter.desktopWidgets;
                if (Array.isArray(saved)) {
                    for (var i = 0; i < saved.length; i++)
                        if (saved[i] && saved[i].id === "music")
                            return saved[i].musicStyle === "line" ? "line" : "ticket";
                }
                return "ticket";
            },
            set: function (value) { root.updateWidget("music", { musicStyle: value }); }
        });
        result.push({
            key: "materialAmeStyle",
            type: "select",
            label: "Material Ame marker",
            caption: "Choose the Material-style animated wave or a straight line.",
            options: ["wave", "line"],
            names: ["Wave", "Straight line"]
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
