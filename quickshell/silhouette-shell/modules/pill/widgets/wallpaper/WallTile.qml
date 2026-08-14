pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.services
import qs.components.animation

/**
 * One wallpaper filmstrip tile. Geometry, brightness and saturation come from
 * the host's slot tables; the focused tile scales up, dims neighbours and
 * carries the hold-to-delete heat fill. `dlProc`/`searchProc` are the host's
 * download and search processes, only read for their running/target state.
 */
Item {
    id: tile

    required property int index
    required property var modelData
    property var host: null
    property var dlProc: null
    property var searchProc: null

    property alias trashHeat: trashHeat

    readonly property string thumb: modelData.thumb !== undefined ? modelData.thumb : ""
    readonly property bool remote: modelData.image !== undefined
    readonly property string thumbSource: remote ? thumb : ("file://" + thumb)

    readonly property real off: index - host.pos
    readonly property real ao: Math.abs(off)
    readonly property bool focused: index === host.focusIndex
    readonly property real bright: host.slotLerp(host.slotBright, ao)
    readonly property real sat: host.slotLerp(host.slotSat, ao)
    readonly property real corner: (8 + 2 * Math.max(0, 1 - ao)) * host.s

    readonly property real hold: trashHeat.hold
    readonly property bool committing: hold >= trashHeat.tapThreshold
    readonly property real commitProgress: Math.max(0, (hold - trashHeat.tapThreshold) / (1 - trashHeat.tapThreshold))

    /**
     * Fade a tile out as its outer edge nears the clipped strip boundary, so
     * the strip ends soften instead of getting hard-cut by the pill's clip.
     */
    readonly property real edgeFade: {
        var soft = 70 * host.s;
        var gap = Math.min(x, host.width - (x + width));
        return Math.max(0, Math.min(1, gap / soft));
    }

    width: host.slotLerp(host.slotW, ao) * host.s
    height: host.slotLerp(host.slotH, ao) * host.s
    x: host.width / 2 + host.offsetX(off) - width / 2
    y: (host.height - height) / 2
    z: 10 - ao
    visible: ao <= 5
    opacity: edgeFade * (ao <= 4 ? 1 : Math.max(0, 5 - ao))

    onFocusedChanged: if (!focused) trashHeat.cancel()

    ClippingRectangle {
        id: card
        anchors.fill: parent
        radius: tile.corner
        color: Theme.tileBg

        layer.enabled: true
        layer.effect: MultiEffect {
            saturation: tile.sat - 1
            shadowEnabled: tile.focused
            shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
            shadowBlur: 0.7
            shadowVerticalOffset: 4 * host.s
        }

        Image {
            id: thumbImage
            anchors.fill: parent
            source: tile.ao <= 6 ? tile.thumbSource : ""
            sourceSize.width: 512
            sourceSize.height: 220
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.tileBg
            visible: thumbImage.status === Image.Error
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 1)
            opacity: 1 - tile.bright
        }

        Rectangle {
            id: consume
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: card.height * tile.commitProgress
            visible: tile.committing
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.vermBurn, 0.66) }
                GradientStop { position: 0.74; color: Qt.alpha(Theme.vermLit, 0.30) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 2 * host.s
                opacity: Math.min(1, tile.commitProgress * 3)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                    GradientStop { position: 0.5; color: Theme.flameGlow }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.flameGlow, 0.0) }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: tile.focused && tile.remote && dlProc.running && dlProc.target === tile.modelData.image
            text: "saving…"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * host.s
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 6 * host.s
            visible: tile.focused && tile.remote && tile.modelData.w > 0 && !(dlProc.running && dlProc.target === tile.modelData.image)
            width: resText.implicitWidth + 12 * host.s
            height: resText.implicitHeight + 5 * host.s
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.55)
            Text {
                id: resText
                anchors.centerIn: parent
                text: tile.modelData.w + "×" + tile.modelData.h
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 9.5 * host.s
                font.features: { "tnum": 1 }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: tile.corner
        color: "transparent"
        border.width: 1
        border.color: {
            if (tile.remote && dlProc.failed.length && dlProc.failed === tile.modelData.image)
                return Theme.vermLit;
            return tile.committing ? Theme.vermLit : Theme.border;
        }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }

    HeatHold {
        id: trashHeat
        tapThreshold: 0.25
        enabled: !tile.remote
        onConfirmed: if (!tile.remote) Walls.trash(tile.modelData.path)
        onTapped: host.activate()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            if (!tile.focused)
                return;
            if (tile.remote)
                host.activate();
            else
                trashHeat.press();
        }
        onReleased: if (tile.focused && !tile.remote) trashHeat.release()
        onExited: trashHeat.cancel()
        onClicked: if (!tile.focused) host.focusIndex = tile.index
    }
}
