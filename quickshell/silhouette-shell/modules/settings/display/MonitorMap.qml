pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Proportional mini-map of the monitor layout for the Display surface: one tile
 * per output (already scaled and positioned by the host's `mapLayout`), the
 * main monitor wearing a star. Dragging a tile reports its drop as a signal so
 * the host can arm a pending arrangement; selection and drag gating come in as
 * plain props, keeping this a pure view.
 */
Item {
    id: map

    property real s: 1.1
    property var tiles: []
    property string selName: ""
    property string mainName: ""
    property var pendingMove: null
    property bool canDrag: false
    property bool busy: false

    signal tilePressed(string name)
    signal tileDropped(string name, real cx, real cy)

    width: parent.width
    Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    Repeater {
        model: map.tiles

        Rectangle {
            id: tile
            required property var modelData

            readonly property bool sel: tile.modelData.name === map.selName
            readonly property bool isMain: tile.modelData.name === map.mainName
            readonly property bool moved: map.pendingMove !== null && map.pendingMove.name === tile.modelData.name
            property real dx: 0
            property real dy: 0

            x: tile.modelData.x + 1.5 * map.s + dx
            y: tile.modelData.y + 1.5 * map.s + dy
            width: Math.max(2, tile.modelData.w - 3 * map.s)
            height: Math.max(2, tile.modelData.h - 3 * map.s)
            z: tileMA.pressed ? 10 : (tile.sel ? 5 : 0)
            radius: 7 * map.s
            color: tile.sel ? Qt.alpha(Theme.onGlow, 0.13) : Theme.cardTop
            border.width: 1
            border.color: tile.moved ? Qt.alpha(Theme.vermLit, 0.7) : (tile.sel ? Theme.cream : Theme.hairSoft)

            Behavior on x { enabled: !tileMA.pressed; NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on y { enabled: !tileMA.pressed; NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            Column {
                anchors.centerIn: parent
                spacing: 2 * map.s

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.modelData.name
                    color: tile.sel ? Theme.cream : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * map.s
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.modelData.hz + "Hz"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 8.5 * map.s
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }

            Text {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 3 * map.s
                anchors.rightMargin: 5 * map.s
                visible: tile.isMain
                text: "★"
                color: Theme.vermLit
                font.family: Theme.fontJp
                font.pixelSize: 9.5 * map.s
            }

            /**
             * Manual drag: local deltas accumulate onto the layout position, so
             * the binding keeps owning x/y and the snap animation plays the
             * moment the deltas reset on release.
             */
            MouseArea {
                id: tileMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : (map.canDrag ? Qt.OpenHandCursor : Qt.PointingHandCursor)
                property real sx: 0
                property real sy: 0
                onPressed: (mouse) => {
                    if (!map.busy)
                        map.tilePressed(tile.modelData.name);
                    sx = mouse.x;
                    sy = mouse.y;
                }
                onPositionChanged: (mouse) => {
                    if (!pressed || !map.canDrag || map.busy)
                        return;
                    tile.dx += mouse.x - sx;
                    tile.dy += mouse.y - sy;
                }
                onReleased: {
                    if (tile.dx !== 0 || tile.dy !== 0)
                        map.tileDropped(tile.modelData.name, tile.x + tile.width / 2, tile.y + tile.height / 2);
                    tile.dx = 0;
                    tile.dy = 0;
                }
            }
        }
    }
}
