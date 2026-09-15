import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root

    visible: true
    width: 1050
    height: 700

    color: "#090909"

    component SidebarItem: Rectangle {
        property string label
        property string icon

        Layout.fillWidth: true
        height: 42
        radius: 10

        color: hover.hovered ? "#242424" : "transparent"

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            Text {
                text: icon
                color: "#cccccc"
                font.pixelSize: 18
                width: 25
            }

            Text {
                text: label
                color: "white"
                font.pixelSize: 15
                verticalAlignment: Text.AlignVCenter
            }
        }

        HoverHandler {
            id: hover
        }
    }


    component SettingsCard: Rectangle {
        default property alias content: layout.data

        width: parent.width
        height: 90

        radius: 16
        color: "#181818"

        RowLayout {
            id: layout

            anchors.fill: parent
            anchors.margins: 20
            spacing: 15
        }
    }


    RowLayout {
        anchors.fill: parent
        spacing: 0


        // Sidebar
        Rectangle {
            Layout.preferredWidth: 260
            Layout.fillHeight: true

            color: "#111111"


            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20

                spacing: 8


                Text {
                    text: "Silhouette"
                    color: "white"

                    font.pixelSize: 28
                    font.bold: true

                    Layout.bottomMargin: 20
                }


                SidebarItem {
                    label: "Appearance"
                    icon: "◐"
                }

                SidebarItem {
                    label: "Motion"
                    icon: "✦"
                }

                SidebarItem {
                    label: "Dynamic Pill"
                    icon: "●"
                }

                SidebarItem {
                    label: "Lock Screen"
                    icon: "▣"
                }


                Item {
                    Layout.fillHeight: true
                }


                SidebarItem {
                    label: "System"
                    icon: "⚙"
                }
            }
        }



        // Content
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true

            color: "#0d0d0d"


            ScrollView {
                anchors.fill: parent
                anchors.margins: 35


                Column {
                    width: parent.width
                    spacing: 20


                    Text {
                        text: "Appearance"

                        color: "white"

                        font.pixelSize: 32
                        font.bold: true
                    }


                    SettingsCard {

                        Text {
                            text: "Theme"
                            color: "white"
                            font.pixelSize: 16
                        }


                        Item {
                            Layout.fillWidth: true
                        }


                        Text {
                            text: "Dark"
                            color: "#aaaaaa"
                        }
                    }



                    SettingsCard {

                        Text {
                            text: "Animations"
                            color: "white"
                            font.pixelSize: 16
                        }


                        Item {
                            Layout.fillWidth: true
                        }


                        Switch {
                            checked: true
                        }
                    }



                    SettingsCard {

                        Text {
                            text: "Blur Amount"
                            color: "white"
                            font.pixelSize: 16
                        }


                        Item {
                            Layout.fillWidth: true
                        }


                        Slider {
                            width: 180
                            value: 0.5
                        }
                    }
                }
            }
        }
    }
}
