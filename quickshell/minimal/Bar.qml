import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick.Layouts
import QtQuick

PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 27

    color: "#111111"

    Rectangle {
        anchors.fill: parent
        color: "#111111"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8


            // LEFT SIDE
            Row {
                id: left

                Layout.alignment: Qt.AlignVCenter

                spacing: 8

                Repeater {
                    model: Hyprland.workspaces.values

                    delegate: Rectangle {
                        width: 22
                        height: 20

                        color: modelData.active
                            ? "#ffffff"
                            : "transparent"

                        Text {
                            anchors.centerIn: parent

                            text: modelData.id

                            color: modelData.active
                                ? "#000000"
                                : "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent

                            onClicked:
                                Hyprland.dispatch(
                                    "workspace " + modelData.id
                                )

                            onWheel: {
                                if (wheel.angleDelta.y > 0)
                                    Hyprland.dispatch("workspace e+1")
                                else
                                    Hyprland.dispatch("workspace e-1")
                            }
                        }
                    }
                }

                Text {
                    visible: Hyprland.currentSubmap !== ""

                    text: Hyprland.currentSubmap

                    color: "white"
                }
            }


            // FILL SPACE
            Item {
                Layout.fillWidth: true
            }


            // RIGHT SIDE
            Row {
                id: right

                Layout.alignment: Qt.AlignVCenter

                spacing: 12

                Text {
                    id: cpu

                    text: "CPU " + usage + "%"

                    property int usage: 0

                    color: "white"
                }


                Text {
                    id: volume

                    color: "white"

                    text: {
                        if (!Pipewire.defaultAudioSink)
                            return "VOL ?"

                        if (Pipewire.defaultAudioSink.muted)
                            return "MUTED"

                        return "VOL " +
                            Math.round(
                                Pipewire.defaultAudioSink.volume * 100
                            ) + "%"
                    }
                }


                Text {
                    id: clock

                    color: "white"

                    function update() {
                        text = Qt.formatDateTime(
                            new Date(),
                            "ddd MMM dd hh:mm AP"
                        )
                    }

                    Component.onCompleted: update()

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true

                        onTriggered: clock.update()
                    }
                }
            }
        }
    }
}
