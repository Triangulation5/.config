pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "Singletons"

/**
 * Now-playing card. Album art bleeds edge-to-edge on the left, faded into the
 * card; a blurred copy glows through a near-opaque warm wash behind everything.
 * Right of the cover: title, artist, a dim source/time line, the play/pause
 * seal (奏/休) flanked by 前/次 skips. Playback runs as a brush stroke along the
 * bottom, its painted head the dock for the pill's soul bead. All now-playing
 * data comes from [[Players]]; when two or more players run, the source token
 * glows into a bubble that opens a picker.
 */
PillSurface {
    id: root

    readonly property var player: Players.active
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: Players.playing
    readonly property string title: Players.has && Players.title ? Players.title : "Nothing playing"
    readonly property string artist: Players.artist
    readonly property bool live: Players.live
    readonly property string serviceLabel: Players.serviceLabel

    /**
     * Art only decodes while this monitor's surface is open, keyed on the track
     * so a browser reusing one file path still reloads on a new song. The shared
     * url means every monitor shows the same cover, never a stale neighbour.
     */
    readonly property string coverSource: {
        if (!root.active)
            return "";
        var u = Players.artUrl;
        if (!u)
            return "";
        return u.indexOf("file:") === 0 ? u + "#" + Players.trackKey : u;
    }
    /** Latched on first decode so the fallback glyph doesn't flash back while a track change reloads behind the retained cover. */
    property bool everReady: false
    onCoverSourceChanged: if (coverSource.length === 0) everReady = false

    /** Source picker is open; only reachable when more than one player runs. */
    property bool picking: false
    readonly property bool canPick: Players.pickable.length > 1
    onActiveChanged: if (!active) picking = false
    onCanPickChanged: if (!canPick) picking = false
    onPickingChanged: if (picking) pickFlick.contentX = 0

    readonly property real textX: 136 * s
    readonly property real edgePad: 18 * s
    readonly property color washMid: mix(Theme.cardTop, Theme.cardBot, 0.5)
    property real sealPulse: 0

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    onTitleChanged: if (playing && active) pulseAnim.restart()

    Timer {
        interval: 500
        running: root.active && root.playing
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged();
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: root; property: "sealPulse"; to: 1; duration: Motion.fast; easing.type: Motion.easeStandard }
        NumberAnimation { target: root; property: "sealPulse"; to: 0; duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    component KanjiSkip: Item {
        id: skip

        property bool can: false
        property string kanjiText: ""
        property string icon: ""
        signal activated()

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Flags.showGlyphs ? kanjiLabel.implicitWidth : 15 * root.s
        implicitHeight: Flags.showGlyphs ? kanjiLabel.implicitHeight : 15 * root.s
        opacity: skip.can ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Text {
            id: kanjiLabel
            visible: Flags.showGlyphs
            anchors.centerIn: parent
            text: skip.kanjiText
            font.family: Theme.fontJp
            font.pixelSize: 13 * root.s
            color: skipArea.containsMouse ? Theme.cream : Theme.dim
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        GlyphIcon {
            visible: !Flags.showGlyphs
            anchors.centerIn: parent
            width: 15 * root.s
            height: 15 * root.s
            name: skip.icon
            color: skipArea.containsMouse ? Theme.cream : Theme.dim
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            id: skipArea
            anchors.fill: parent
            anchors.margins: -6 * root.s
            hoverEnabled: true
            enabled: skip.can
            cursorShape: Qt.PointingHandCursor
            onClicked: skip.activated()
        }
    }

    /** Round album swatch that tags a source, falls back to a warm tile. */
    component ArtDot: ClippingRectangle {
        id: dot
        property string url: ""
        radius: width / 2
        color: Theme.tileBg
        Image {
            anchors.fill: parent
            source: dot.url
            sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        topLeftRadius: Flags.notchStyle ? 0 : 22 * root.s
        topRightRadius: Flags.notchStyle ? 0 : 22 * root.s
        bottomLeftRadius: 22 * root.s
        bottomRightRadius: 22 * root.s

        color: "transparent"

        Image {
            id: bleedSrc
            anchors.fill: parent
            source: root.coverSource
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            cache: String(source).indexOf("file:") !== 0
            visible: false
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.cardTop, 0.88) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.cardBot, 0.93) }
            }
        }

        ClippingRectangle {
            id: coverBox

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16 * root.s

            width: parent.height - 42 * root.s
            height: width

            radius: 16 * root.s
            color: Theme.tileBg

            Rectangle {
                anchors.fill: parent
                color: Theme.tileBg
                visible: !root.everReady
            }

            Image {
                id: cover
                anchors.fill: parent
                source: root.coverSource
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                cache: String(source).indexOf("file:") !== 0

                onStatusChanged: {
                    if (status === Image.Ready)
                        root.everReady = true
                }
            }

            GlyphIcon {
                anchors.centerIn: parent
                width: 40 * root.s
                height: width
                name: "music"
                color: Theme.subtle
                visible: !root.everReady
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.textX
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.top: parent.top
        anchors.topMargin: 24 * root.s
        spacing: 3 * root.s

        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.title
            color: Theme.cream
            pixelSize: 21 * root.s
            weight: Font.DemiBold
            active: root.active
        }

        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.artist
            color: Theme.dim
            pixelSize: 16 * root.s
            active: root.active
            visible: text.length > 0
        }
    }

    Row {
        id: transport
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 * root.s
        spacing: 14 * root.s
        opacity: root.picking ? 0 : 1
        enabled: !root.picking
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        transform: Translate {
            x: -146 * root.s
        }

        KanjiSkip {
            kanjiText: "前"
            icon: "prev"

            can: root.hasPlayer &&
                 root.player.canGoPrevious

            onActivated: {
                if (root.player)
                    root.player.previous()
            }
        }

        Rectangle {
            id: seal

            anchors.verticalCenter: parent.verticalCenter

            width: 30 * root.s
            height: 30 * root.s

            radius: 7 * root.s

            rotation: -1.5
            scale: 1 + 0.08 * root.sealPulse

            property real sat:
                root.playing ? 1 : 0

            Behavior on sat {
                NumberAnimation {
                    duration: Motion.fast
                    easing.type: Motion.easeStandard
                }
            }

            opacity:
                (sealArea.enabled ? 1 : 0.4) *
                (0.75 + 0.25 * sat)

            Behavior on opacity {
                NumberAnimation {
                    duration: Motion.fast
                }
            }

            border.width: 1

            border.color:
                Qt.alpha(
                    Theme.vermLit,
                    0.4 + 0.4 * root.sealPulse
                )

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: root.mix(
                        Theme.verm,
                        Theme.tileBg,
                        0.55 - 0.27 * seal.sat
                    )
                }

                GradientStop {
                    position: 1.0
                    color: root.mix(
                        Theme.vermDeep,
                        Theme.tileBg,
                        0.55 - 0.27 * seal.sat
                    )
                }
            }

            Text {
                visible: Flags.showGlyphs

                anchors.centerIn: parent

                text: root.playing
                      ? "奏"
                      : "休"

                color: "#ffffff"

                font.family: Theme.fontJp
                font.pixelSize: 16 * root.s
                font.weight: Font.Bold
            }

            GlyphIcon {
                visible: !Flags.showGlyphs

                anchors.centerIn: parent

                width: 15 * root.s
                height: 15 * root.s

                name: root.playing
                      ? "pause"
                      : "play"

                color: "#ffffff"
            }

            MouseArea {
                id: sealArea

                anchors.fill: parent
                anchors.margins: -4 * root.s

                hoverEnabled: true

                enabled: root.hasPlayer &&
                         root.player.canTogglePlaying

                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    if (root.player)
                        root.player.togglePlaying()
                }
            }
        }

        KanjiSkip {
            kanjiText: "次"
            icon: "next"

            can: root.hasPlayer &&
                 root.player.canGoNext

            onActivated: {
                if (root.player)
                    root.player.next()
            }
        }
    }
}
