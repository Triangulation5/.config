pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Singletons"

Item {
    id: root

    property real s: 1
    property bool open: false
    property var focusRowItem: null

    signal closeRequested()

    function reportRowHover(row, hovered) {
        if (hovered)
            focusRowItem = row;
    }

    function activateRow(row) {
        if (row === closeRow) {
            closeRequested();
            return;
        }

        if (row.name === "Music Visualizer")
            Flags.musicVisualizer = !Flags.musicVisualizer;

        if (row.name === "24 Hour Time")
            Flags.time12h = !Flags.time12h;
    }

    width: 330 * s
    height: panelContent.height + 28 * s

    visible: open
    opacity: open ? 1 : 0

    anchors.right: parent.right
    anchors.bottom: parent.bottom

    anchors.rightMargin: 32 * s
    anchors.bottomMargin: 90 * s

    Behavior on opacity {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent

        radius: 22 * s

        color: Theme.capsule

        border.width: 1
        border.color: Theme.capsuleBorder

        layer.enabled: true

        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.7
            shadowVerticalOffset: 6
            shadowColor: Qt.rgba(0,0,0,0.3)
        }
    }

    Column {
        id: panelContent

        width: parent.width

        anchors.top: parent.top
        anchors.left: parent.left

        anchors.margins: 14 * s

        spacing: 4 * s


        SettingsHeader {
            width: parent.width
            s: root.s
            title: "Settings"
        }


        SettingsRow {
            id: visualizerRow

            surface: root

            icon: "eye"
            name: "Music Visualizer"

            sub: Flags.musicVisualizer
                ? "Enabled"
                : "Disabled"

            Item {
                width: 38 * root.s
                height: 18 * root.s

                Rectangle {
                    anchors.fill: parent

                    radius: height / 2

                    color: Flags.musicVisualizer
                        ? Theme.verm
                        : Theme.fieldBorder


                    Rectangle {
                        width: 12 * root.s
                        height: width

                        radius: width / 2

                        anchors.verticalCenter: parent.verticalCenter

                        x: Flags.musicVisualizer
                            ? parent.width - width - 3 * root.s
                            : 3 * root.s

                        color: Theme.cream
                    }
                }
            }
        }


        SettingsRow {
            id: timeRow

            surface: root

            icon: "clock"
            name: "24 Hour Time"

            sub: Flags.time12h
                ? "12 hour clock"
                : "24 hour clock"

            Item {
                width: 38 * root.s
                height: 18 * root.s

                Text {
                    anchors.centerIn: parent

                    text: Flags.time12h
                        ? "12"
                        : "24"

                    color: Theme.cream

                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                }
            }
        }


        SettingsRow {
            surface: root

            icon: "cog"
            name: "Display"
            sub: "Appearance"
        }


        SettingsRow {
            surface: root

            icon: "wifi"
            name: "Network"
            sub: "Connection"
        }


        SettingsRow {
            surface: root

            icon: "lock"
            name: "Power"
            sub: "System actions"
        }


        Rectangle {
            width: parent.width
            height: 1

            color: Theme.hairSoft
        }


        SettingsRow {
            id: closeRow

            surface: root

            icon: "chevron-left"
            name: "Close"

            last: true
        }
    }
}
