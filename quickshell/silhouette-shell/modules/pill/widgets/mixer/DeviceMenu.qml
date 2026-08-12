pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * Device dropdown overlay for the mixer. Both output and input pickers reuse
 * this: `kind` keys it to the host's openPicker, `model` is the node list,
 * `current` is the active default, and `onPick` writes the chosen node. It
 * floats above the faders right-aligned under the header so the mixer height
 * stays fixed while a list is open. `deviceLabel` is a callback that
 * resolves a node to its display name.
 */
Item {
    id: menu

    property real s: 1.1
    property string kind: ""
    property var model: []
    property var current
    /** Callback (node) → string: resolves a device node to a display label. */
    property var deviceLabel: function() { return ""; }
    /** True while the host's openPicker matches `kind`. */
    property bool open: false
    signal pick(var node)

    z: 7
    visible: open
    width: 300 * s
    height: panel.height

    /** Shadow caster kept apart from the option text so glyphs stay crisp. */
    Rectangle {
        anchors.fill: panel
        visible: menu.open
        radius: panel.radius
        color: Theme.cardBot
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.6
            shadowVerticalOffset: 4 * s
        }
    }

    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(menu.model.length * 24 * s + 4 * s, 150 * s)
        clip: true
        radius: 9 * s
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.cardTop }
            GradientStop { position: 1.0; color: Theme.cardBot }
        }
        border.width: 1
        border.color: Theme.frameBorder

        ListView {
            anchors.fill: parent
            anchors.margins: 2 * s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: menu.model

            delegate: Rectangle {
                id: devRow
                required property var modelData
                readonly property bool current: menu.current === modelData

                width: ListView.view.width
                height: 24 * s
                radius: 7 * s
                color: devRowHover.hovered ? Theme.frameBg
                    : (devRow.current ? Qt.alpha(Theme.onGlow, 0.16) : "transparent")

                HoverHandler { id: devRowHover }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * s
                    anchors.right: parent.right
                    anchors.rightMargin: 9 * s
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.deviceLabel(devRow.modelData)
                    elide: Text.ElideRight
                    color: devRow.current ? Theme.cream : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10.5 * s
                    font.weight: devRow.current ? Font.Bold : Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        menu.pick(devRow.modelData);
                        menu.open = false;
                    }
                }
            }
        }
    }
}
