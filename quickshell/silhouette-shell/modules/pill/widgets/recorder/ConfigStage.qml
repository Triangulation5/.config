pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services
import qs.modules.controlcenter
import qs.components.icons
import qs.modules.pill.widgets

/**
 * The Recorder's config stage: a tappable card showing the recording spec
 * (title + fps · quality) that folds open an options drawer — frame rate,
 * quality, capture cursor and countdown. Pure view: state comes in as props
 * and the tap goes out as a signal, so the host owns drawer visibility and the
 * recording flow. The drawer controls drive ScreenRec/Flags directly.
 */
Item {
    id: stage

    property real s: 1.1
    property bool drawerOpen: false
    property bool chooserOpen: false
    property bool counting: false
    property bool recording: false
    property string title: ""
    property string spec: ""

    signal toggleRequested()

    width: parent.width
    height: stageCard.height + drawer.height

    Rectangle {
        id: stageCard
        property bool pressActive: false
        width: parent.width
        height: 76 * stage.s
        radius: 13 * stage.s
        color: Theme.cardBot
        transformOrigin: Item.Center
        scale: pressActive ? 0.984 : 1
        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius + 1
            visible: stage.drawerOpen
            color: Theme.cardBot
        }

        Repeater {
            model: [
                { hx: false, vy: false },
                { hx: true, vy: false },
                { hx: false, vy: true },
                { hx: true, vy: true }
            ]

            Item {
                id: corner
                required property var modelData
                readonly property color arm: Qt.alpha(Theme.vermLit, 0.5)
                width: 14 * stage.s
                height: 14 * stage.s
                opacity: stage.counting || stage.recording
                    || (modelData.vy && stage.drawerOpen) ? 0 : 1
                x: modelData.hx ? stageCard.width - width - 11 * stage.s : 11 * stage.s
                y: modelData.vy ? stageCard.height - height - 11 * stage.s : 11 * stage.s
                rotation: modelData.hx ? (modelData.vy ? 180 : 90) : (modelData.vy ? 270 : 0)
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: corner.arm
                        strokeWidth: 2 * stage.s
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 1 * stage.s
                        startY: 13 * stage.s
                        PathLine { x: 1 * stage.s; y: 5.5 * stage.s }
                        PathQuad { controlX: 1 * stage.s; controlY: 1 * stage.s; x: 5.5 * stage.s; y: 1 * stage.s }
                        PathLine { x: 13 * stage.s; y: 1 * stage.s }
                    }
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 22 * stage.s
            anchors.right: chevron.left
            anchors.rightMargin: 12 * stage.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * stage.s

            Text {
                width: parent.width
                text: stage.title
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * stage.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Row {
                width: parent.width
                spacing: 6 * stage.s

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5 * stage.s
                    height: 5 * stage.s
                    radius: width / 2
                    color: stage.recording ? Theme.verm : Theme.vermDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stage.spec
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10.5 * stage.s
                    font.features: { "tnum": 1 }
                    elide: Text.ElideRight
                }
            }
        }

        Row {
            visible: stage.recording
            anchors.right: parent.right
            anchors.rightMargin: 16 * stage.s
            anchors.top: parent.top
            anchors.topMargin: 13 * stage.s
            spacing: 5 * stage.s

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6 * stage.s
                height: 6 * stage.s
                radius: width / 2
                color: Theme.verm
            }
            Text {
                text: "REC"
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 8.5 * stage.s
                font.weight: Font.ExtraBold
                font.letterSpacing: 1.2 * stage.s
            }
        }

        GlyphIcon {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 14 * stage.s
            anchors.verticalCenter: parent.verticalCenter
            width: 13 * stage.s
            height: 13 * stage.s
            name: "chevron-down"
            color: stage.drawerOpen ? Theme.vermLit : Theme.faint
            stroke: 2.2
            rotation: stage.drawerOpen ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: stageCard.pressActive = true
            onReleased: stageCard.pressActive = false
            onCanceled: stageCard.pressActive = false
            onClicked: if (!stage.recording && !stage.counting && !stage.chooserOpen)
                stage.toggleRequested()
        }
    }

    Item {
        id: drawer
        anchors.top: stageCard.bottom
        width: parent.width
        height: stage.drawerOpen ? drawerCol.implicitHeight : 0
        clip: true
        visible: height > 0
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        Rectangle {
            anchors.fill: parent
            radius: 13 * stage.s
            color: Theme.cardBot
        }
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 13 * stage.s + 1
            color: Theme.cardBot
        }

        Column {
            id: drawerCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 18 * stage.s
            anchors.rightMargin: 16 * stage.s
            topPadding: 2 * stage.s
            bottomPadding: 10 * stage.s

            ORow {
                s: stage.s
                name: "Frame rate"
                first: true
                MiniSeg {
                    s: stage.s
                    options: [
                        { label: "30", value: 30 },
                        { label: "60", value: 60 },
                        { label: "120", value: 120 },
                        { label: "144", value: 144 }
                    ]
                    value: ScreenRec.fps
                    onPicked: (v) => ScreenRec.fps = v
                }
            }
            ORow {
                s: stage.s
                name: "Quality"
                MiniSeg {
                    s: stage.s
                    options: [
                        { label: "Med", value: "medium" },
                        { label: "High", value: "high" },
                        { label: "Ultra", value: "ultra" },
                        { label: "Loss", value: "lossless" }
                    ]
                    value: ScreenRec.quality
                    onPicked: (v) => ScreenRec.quality = v
                }
            }
            ORow {
                s: stage.s
                name: "Capture cursor"
                LinkToggle {
                    s: stage.s
                    on: ScreenRec.captureCursor
                    onToggled: ScreenRec.captureCursor = !ScreenRec.captureCursor
                }
            }
            ORow {
                s: stage.s
                name: "Countdown"
                MiniSeg {
                    s: stage.s
                    options: [
                        { label: "Off", value: 0 },
                        { label: "3s", value: 3 },
                        { label: "5s", value: 5 },
                        { label: "10s", value: 10 }
                    ]
                    value: Flags.recordCountdown
                    onPicked: (v) => Flags.recordCountdown = v
                }
            }
        }
    }
}
