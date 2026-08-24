pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.services
import qs.components.icons
import qs.modules.pill.widgets.osd

/**
 * Now-playing OSD face: cover art with the source app badge, title/artist and
 * a play state glyph. Exposes `coverReady` so the Osd root can hold a track
 * flash open until a late cover decodes, and emits `artReady` when art that
 * lands mid-flash is finally readable.
 */
OsdFace {
    id: face

    property string art: ""
    property string icon: ""
    property string title: ""
    property string artist: ""
    property bool playing: false

    /** True once the current art has decoded, for the root's hold-open logic. */
    readonly property bool coverReady: cover.status === Image.Ready

    /** Emitted when cover art finishes decoding, so the root can extend its hold. */
    signal artReady()

    ClippingRectangle {
        id: coverBox
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 44 * face.s
        height: 44 * face.s
        radius: 9 * face.s
        color: Theme.tileBg

        Image {
            id: cover
            anchors.fill: parent
            source: face.art
            sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: String(source).indexOf("file:") !== 0
            opacity: status === Image.Ready ? 1 : 0
            /** Art that arrives late still earns a moment on screen. */
            onStatusChanged: if (status === Image.Ready) face.artReady()
        }
        GlyphIcon {
            anchors.centerIn: parent
            width: parent.width * 0.42
            height: width
            name: "music"
            color: Theme.subtle
            visible: cover.status !== Image.Ready
        }

        /** The source's own app icon, sat as a small badge on the art corner. */
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 3 * face.s
            width: 18 * face.s
            height: 18 * face.s
            radius: width / 2
            color: Qt.alpha(Theme.cardBot, 0.8)
            visible: srcIcon.status === Image.Ready

            Image {
                id: srcIcon
                anchors.centerIn: parent
                width: 12 * face.s
                height: 12 * face.s
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: face.icon
            }
        }
    }

    GlyphIcon {
        id: trackCtrl
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 18 * face.s
        height: 18 * face.s
        name: face.playing ? "play" : "pause"
        color: face.playing ? Theme.vermLit : Theme.iconDim
    }

    Column {
        anchors.left: coverBox.right
        anchors.leftMargin: 12 * face.s
        anchors.right: trackCtrl.left
        anchors.rightMargin: 12 * face.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * face.s

        Text {
            width: parent.width
            text: face.title.length > 0 ? face.title : "Nothing playing"
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 14 * face.s
            font.weight: Font.DemiBold
            maximumLineCount: 1
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: face.artist
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * face.s
            maximumLineCount: 1
            elide: Text.ElideRight
            visible: text.length > 0
        }
    }
}
