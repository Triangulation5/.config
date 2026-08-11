pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls
import qs.components.icons

/**
 * Standalone quick-record source chooser. Driven by the SUPER+D keybind with
 * no recorder surface open: it grows the pill on the focused monitor only
 * (mode "quickChoose") and offers the same Screen and Window / Region picks as
 * the surface. Screen with one monitor resolves at once; several monitors flip
 * to the inline sub-choice. A pick fires ScreenRec.prepareScreen / prepareWindow
 * through the pill (which owns that routing) -> targetReady -> the central
 * countdown, then closes.
 */
Item {
    id: root

    property real s: 1.1

    /** True while the quick-choose mode owns the pill. */
    property bool active: false

    /** How settled the pill is into its target geometry; drives the fade-in. */
    property real morph: 0

    /** A source tile was picked; the pill routes it into ScreenRec. */
    signal pickSource(string kind)

    /** A monitor tile was picked in the multi-screen sub-choice. */
    signal pickMonitor(string name)

    enabled: root.active
    opacity: root.active ? Math.pow(root.morph, 1.3) : 0
    visible: opacity > 0.01
    Behavior on opacity {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Row {
        id: quickSources
        anchors.fill: parent
        visible: !ScreenRec.quickScreenChoosing
        spacing: 6 * root.s

        Repeater {
            model: [
                { kind: "screen", label: "Screen", glyph: "monitor" },
                { kind: "window", label: "Window / Region", glyph: "video" }
            ]

            Rectangle {
                id: qSrcTile
                required property var modelData
                width: (quickSources.width - 6 * root.s) / 2
                height: parent.height
                radius: 11 * root.s
                color: qSrcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                border.width: 1
                border.color: qSrcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Row {
                    anchors.centerIn: parent
                    spacing: 8 * root.s

                    GlyphIcon {
                        width: 16 * root.s
                        height: 16 * root.s
                        name: qSrcTile.modelData.glyph
                        color: qSrcArea.containsMouse ? Theme.vermLit : Theme.iconDim
                        stroke: 1.7
                    }
                    Text {
                        height: 16 * root.s
                        verticalAlignment: Text.AlignVCenter
                        text: qSrcTile.modelData.label
                        color: qSrcArea.containsMouse ? Theme.cream : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    id: qSrcArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickSource(qSrcTile.modelData.kind)
                }
            }
        }
    }

    ListView {
        id: quickScreens
        anchors.fill: parent
        anchors.rightMargin: 22 * root.s
        visible: ScreenRec.quickScreenChoosing
        orientation: ListView.Horizontal
        spacing: 6 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: ScreenRec.monitors

        delegate: Rectangle {
            id: qMonTile
            required property var modelData
            width: 152 * root.s
            height: quickScreens.height
            radius: 11 * root.s
            color: qMonArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
            border.width: 1
            border.color: qMonArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Column {
                anchors.centerIn: parent
                spacing: 2 * root.s

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qMonTile.modelData.name
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11.5 * root.s
                    font.weight: Font.Bold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qMonTile.modelData.w + " × " + qMonTile.modelData.h
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 9.5 * root.s
                    font.features: { "tnum": 1 }
                }
            }

            MouseArea {
                id: qMonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickMonitor(qMonTile.modelData.name)
            }
        }
    }

    WheelScroller {
        flick: quickScreens
        s: root.s
        anchors.fill: quickScreens
        visible: ScreenRec.quickScreenChoosing
    }

    GlyphIcon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5 * root.s
        visible: ScreenRec.quickScreenChoosing
        width: 12 * root.s
        height: 12 * root.s
        name: "chevron-left"
        color: qBackArea.containsMouse ? Theme.cream : Theme.faint
        stroke: 2

        MouseArea {
            id: qBackArea
            anchors.fill: parent
            anchors.margins: -7 * root.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ScreenRec.quickScreenChoosing = false
        }
    }
}
