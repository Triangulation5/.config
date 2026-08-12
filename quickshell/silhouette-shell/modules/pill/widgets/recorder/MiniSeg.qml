pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Mini-segmented choice control — `options` is a list of `{ label, value }`;
 * the pill whose value equals `value` lights with a solid card-top fill and
 * cream text. Picking a pill emits `picked(value)`.
 */
Rectangle {
    id: seg

    property real s: 1.1
    property var options: []
    property var value
    signal picked(var value)

    readonly property real pad: 2 * s

    width: pills.implicitWidth + 2 * pad
    height: pills.implicitHeight + 2 * pad
    radius: 9 * s
    color: "transparent"

    Row {
        id: pills
        anchors.centerIn: parent
        spacing: 2 * s

        Repeater {
            model: seg.options

            Rectangle {
                id: opt
                required property var modelData
                readonly property bool current: seg.value === modelData.value

                width: optLabel.implicitWidth + 18 * s
                height: optLabel.implicitHeight + 12 * s
                radius: 7 * s
                color: opt.current ? Theme.cardTop : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: optLabel
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.current ? Theme.cream : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10.5 * s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3 * s
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}
