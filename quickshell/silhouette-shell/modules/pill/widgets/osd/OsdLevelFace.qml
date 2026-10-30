pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons
import qs.modules.pill.widgets.osd

/**
 * Level OSD face: a glyph at the left, a percentage at the right and a fill
 * bar between them that tracks `fill`. Shared by the volume, brightness and
 * power-source faces, which only differ in glyph, glyph colour, percentage and
 * fill styling. Driven by the Osd root through `active`.
 */
OsdFace {
    id: face

    property string glyph: ""
    property string title: "Level"
    property color glyphColor: Theme.iconDim
    property real glyphProgress: 1

    property string pctText: ""
    property color pctColor: Theme.cream
    property real pctWidth: 32 * face.s

    property real fill: 0
    property color levelFillColor: Theme.primary
    property bool levelInteractive: false
    property bool iconInteractive: false
    signal levelRequested(real value)
    signal iconClicked()
    property real dragValue: 0
    property bool dragging: false
    readonly property real displayFill: dragging ? dragValue : fill

    Rectangle {
        id: iconContainer
        anchors.left: parent.left
        anchors.leftMargin: 4 * face.s
        anchors.verticalCenter: parent.verticalCenter
        width: 38 * face.s
        height: width
        radius: 14 * face.s
        color: Theme.primaryContainer

        MouseArea {
            anchors.fill: parent
            enabled: face.iconInteractive
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: face.iconClicked()
        }
    }

    GlyphIcon {
        id: levelGlyph
        anchors.centerIn: iconContainer
        width: 18 * face.s
        height: 17 * face.s
        name: face.glyph
        progress: face.glyphProgress
        color: face.glyphColor
        stroke: 1.7
    }

    Text {
        id: titleLabel
        anchors.left: iconContainer.right
        anchors.leftMargin: 12 * face.s
        anchors.right: pctLabel.left
        anchors.rightMargin: 6 * face.s
        anchors.top: parent.top
        anchors.topMargin: 7 * face.s
        text: face.title
        color: Theme.onSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 11 * face.s
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    Text {
        id: pctLabel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 7 * face.s
        anchors.rightMargin: 5 * face.s
        width: face.pctWidth
        horizontalAlignment: Text.AlignRight
        text: face.pctText
        color: face.pctColor
        font.family: Theme.font
        font.pixelSize: 12 * face.s
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        Behavior on color {
            enabled: Style.transitioning
            ColorAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
        }
    }

    Rectangle {
        anchors.left: iconContainer.right
        anchors.leftMargin: 12 * face.s
        anchors.right: parent.right
        anchors.rightMargin: 5 * face.s
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9 * face.s
        height: 8 * face.s
        radius: height / 2
        color: Theme.surfaceContainerHighest
        clip: true
        Behavior on color {
            enabled: Style.transitioning
            ColorAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
        }

        Rectangle {
            id: levelFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * face.displayFill
            radius: parent.radius
            color: face.levelFillColor
            Behavior on width { NumberAnimation { duration: Motion.fast } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - width / 2
                width: 10 * face.s
                height: width
                radius: width / 2
                color: face.levelFillColor
                visible: face.displayFill > 0
                Behavior on color {
                    enabled: Style.transitioning
                    ColorAnimation { duration: Style.transitionDuration; easing.type: Easing.InOutCubic }
                }
            }

        }

        MouseArea {
            anchors.fill: parent
            enabled: face.levelInteractive && face.active
            preventStealing: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

            function setFromX(x) {
                face.dragValue = Math.max(0, Math.min(1, x / width));
            }

            onPressed: mouse => {
                face.dragging = true;
                setFromX(mouse.x);
            }
            onPositionChanged: mouse => {
                if (pressed)
                    setFromX(mouse.x);
            }
            onReleased: {
                face.levelRequested(face.dragValue);
                face.dragging = false;
            }
            onCanceled: face.dragging = false
        }
    }
}
