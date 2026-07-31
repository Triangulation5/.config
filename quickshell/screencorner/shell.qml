import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "Singletons"

PanelWindow {
    id: corners

    visible: true
    color: "transparent"

    WlrLayershell.namespace: "quickshell:screen-corners"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore


    readonly property int cornerSize: 16
    readonly property color cornerColor: Theme.capsule


    property bool menuOpen: false

    property real morphProgress: menuOpen ? 1 : 0

    property real earProgress: menuOpen ? 1 : 0

    property real edgeEarProgress: menuOpen ? 1 : 0



    Behavior on morphProgress {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }


    Behavior on earProgress {
        NumberAnimation {
            duration: menuOpen ? 420 : 260
            easing.type: Easing.OutCubic
        }
    }


    Behavior on edgeEarProgress {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }



    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }



    Repeater {
        model: [
            { h: Qt.AlignLeft,  v: Qt.AlignTop,    c: RoundCorner.CornerEnum.TopLeft },
            { h: Qt.AlignRight, v: Qt.AlignTop,    c: RoundCorner.CornerEnum.TopRight },
            { h: Qt.AlignLeft,  v: Qt.AlignBottom, c: RoundCorner.CornerEnum.BottomLeft },
            { h: Qt.AlignRight, v: Qt.AlignBottom, c: RoundCorner.CornerEnum.BottomRight }
        ]

        delegate: RoundCorner {

            visible: !corners.menuOpen

            size: corners.cornerSize
            corner: modelData.c
            color: corners.cornerColor

            anchors {
                left: modelData.h === Qt.AlignLeft ? parent.left : undefined
                right: modelData.h === Qt.AlignRight ? parent.right : undefined
                top: modelData.v === Qt.AlignTop ? parent.top : undefined
                bottom: modelData.v === Qt.AlignBottom ? parent.bottom : undefined
            }
        }
    }



    Item {
        id: menuContainer

        anchors {
            right: parent.right
            bottom: parent.bottom
        }

        width: menu.width + 56
        height: menu.height + 56



        // Top-right expanded ear
        // Same shape as original bottom-right screen corner
        RoundCorner {
            z: 1

            visible: corners.edgeEarProgress > 0

            opacity: corners.edgeEarProgress
            scale: corners.edgeEarProgress

            transformOrigin: Item.BottomRight


            anchors {
                right: menu.right
                top: menu.top
            }

            anchors.rightMargin: -1
            anchors.topMargin: -26


            size: menu.radius * corners.edgeEarProgress

            corner: RoundCorner.CornerEnum.BottomRight

            color: corners.cornerColor
        }



        // Bottom-left expanded ear
        RoundCorner {
            z: 1

            visible: corners.edgeEarProgress > 0

            opacity: corners.edgeEarProgress
            scale: corners.edgeEarProgress

            transformOrigin: Item.TopLeft


            anchors {
                left: menu.left
                bottom: menu.bottom
            }

            anchors.leftMargin: -1
            anchors.bottomMargin: -1


            size: menu.radius * corners.edgeEarProgress

            corner: RoundCorner.CornerEnum.TopLeft

            color: corners.cornerColor
        }



        // Left expansion ear
        RoundCorner {
            z: 0

            visible: corners.earProgress > 0

            opacity: corners.earProgress
            scale: corners.earProgress

            transformOrigin: Item.BottomRight


            anchors {
                right: menu.left
                bottom: menu.bottom
            }

            anchors.rightMargin: -1
            anchors.bottomMargin: -1


            size: menu.radius * corners.earProgress

            corner: RoundCorner.CornerEnum.BottomRight

            color: corners.cornerColor
        }



        // Right expansion ear
        RoundCorner {
            z: 0

            visible: corners.earProgress > 0

            opacity: corners.earProgress
            scale: corners.earProgress

            transformOrigin: Item.BottomLeft


            anchors {
                left: menu.right
                bottom: menu.bottom
            }

            anchors.leftMargin: -1
            anchors.bottomMargin: -1


            size: menu.radius * corners.earProgress

            corner: RoundCorner.CornerEnum.BottomLeft

            color: corners.cornerColor
        }



        Rectangle {
            id: menu

            z: 2


            property real radius: 28


            anchors {
                right: parent.right
                bottom: parent.bottom
            }


            width: 56 + (360 - 56) * corners.morphProgress
            height: 56 + (240 - 56) * corners.morphProgress


            color: Theme.capsule

            antialiasing: true
            clip: false



            topLeftRadius: radius

            // top-right becomes flat when expanded so the ear forms the curve
            topRightRadius: radius * (1 - corners.morphProgress)

            bottomLeftRadius: radius * (1 - corners.morphProgress)
            bottomRightRadius: radius * (1 - corners.morphProgress)



            Behavior on width {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }


            Behavior on height {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }



            scale: mouse.pressed ? 0.96 : 1


            Behavior on scale {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }



            layer.enabled: true

            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowOpacity: 0.28
                shadowBlur: 0.7
                shadowVerticalOffset: 4
            }



            MouseArea {
                id: mouse

                anchors.fill: parent

                onClicked: {
                    corners.menuOpen = !corners.menuOpen
                    corners.earProgress = corners.menuOpen ? 1 : 0
                    corners.edgeEarProgress = corners.menuOpen ? 1 : 0
                }
            }



            Text {
                id: cog

                anchors.centerIn: parent

                text: "⚙"

                color: "white"

                font.pixelSize: 24


                opacity: 1 - corners.morphProgress

                scale: 1 - corners.morphProgress * 0.3


                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }



            Column {
                anchors.fill: parent
                anchors.margins: 24

                spacing: 12


                opacity: corners.morphProgress > 0.2
                         ? corners.morphProgress
                         : 0


                scale: 0.92 + corners.morphProgress * 0.08


                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                    }
                }



                Label {
                    text: "Settings"

                    color: "white"

                    font.pixelSize: 20
                    font.bold: true
                }



                Repeater {
                    model: [
                        "Display",
                        "Audio",
                        "Bluetooth",
                        "Power"
                    ]

                    delegate: Rectangle {

                        width: parent.width
                        height: 42

                        radius: 12

                        color: Qt.lighter(
                            Theme.capsule,
                            1.08
                        )


                        Label {
                            anchors.centerIn: parent

                            text: modelData
                            color: "white"
                        }
                    }
                }
            }
        }
    }
}
