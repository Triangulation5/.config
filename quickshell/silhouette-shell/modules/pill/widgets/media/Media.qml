pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.services
import qs.modules.pill.surfaces
import qs.components.animation
import qs.components.icons

/**
 * Now-playing card. Its backdrop follows Flags.mediaStyle, chosen in
 * Appearance: "bleed" — a blurred, low-res copy of the cover stretching
 * across the card, subtle and riding the pill's own opacity; "wash" — the
 * legacy near-opaque warm tint, verbatim; or "none" — fully transparent,
 * the pill body reading through like every other surface. The album art
 * itself always sits in a rounded tile on the left. Right of the cover:
 * title, artist, a dim source/time line, the play/pause seal (奏/休) flanked
 * by 前/次 skips. Playback runs as a brush stroke along the bottom, its
 * painted head the dock for the pill's soul bead. All now-playing data
 * comes from [[Players]]; when two or more players run, the source token
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
     * True while the card is actually on screen. Drives the marquees and the
     * 2Hz position poll so neither runs while the card is invisible. The host
     * supplies it: the full media surface passes its open state, and the hover
     * bud passes the pill's hover mode (the bud stays instantiated with
     * open: true even at rest, so `open` alone can't gate it). Defaults off.
     */
    property bool shown: false

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
    /**
     * Latched on first decode so the fallback glyph doesn't flash back while a
     * track change reloads behind the retained cover. Reset on an empty art
     * URL; an Error status also drops the latch so the chain below can step
     * down to the app icon.
     */
    property bool everReady: false
    onCoverSourceChanged: if (coverSource.length === 0) everReady = false

    /** Second rung of the art fallback chain: the player's own app icon. */
    readonly property string appIcon: hasPlayer ? Players.appIconFor(player) : ""
    /**
     * Whether the track itself carries art. Keyed on the player's art URL, not
     * on the transient `coverSource` (which empties whenever the surface is
     * inactive), so the fallback chain never flashes the app icon during the
     * open/close morph on a track that does have art.
     */
    readonly property bool hasArt: hasPlayer && Players.artUrl && Players.artUrl.length > 0
    /** True while the app icon is being shown in the cover tile — only when the track has no art at all. */
    readonly property bool artFallbackIcon: !root.hasArt && root.appIcon.length > 0

    /** Source picker is open; only reachable when more than one player runs. */
    property bool picking: false
    readonly property bool canPick: Players.pickable.length > 1
    onActiveChanged: if (!active) picking = false
    onCanPickChanged: if (!canPick) picking = false
    onPickingChanged: if (picking) pickFlick.contentX = 0

    readonly property real textX: 148 * s
    readonly property real edgePad: 18 * s

    /** Card backdrop mode from Appearance: "bleed", "wash", or "none". */
    readonly property bool bleedOn: Flags.mediaStyle === "bleed"
    readonly property bool washOn: Flags.mediaStyle === "wash"

    /**
     * Strength of the blurred cover bleed behind the card. Subtle on purpose:
     * it lifts the now-playing view off the flat pill body with the track's
     * own palette, and it scales with the pill's surface opacity
     * (Flags.pillOpacity) so a translucent pill stays uniformly translucent —
     * never a hard band like the old flat wash.
     */
    readonly property real artBleed: 0.28 * Flags.pillOpacity

    /**
     * Warm wash base for the legacy tint option (Flags.mediaStyle "wash"):
     * the card's original near-opaque verm glow, kept verbatim so the option
     * restores exactly what the surface looked like before the bleed.
     */
    readonly property color washMid: Theme.mix(Theme.cardTop, Theme.verm, 0.14)

    /** Cover tile tone: warm-tinted under the legacy wash, standard shell tile dark otherwise. */
    readonly property color tileTone: root.washOn ? Theme.mix(Theme.tileBg, root.washMid, 0.5) : Theme.tileBg

    property real sealPulse: 0

    onTitleChanged: if (playing && active) pulseAnim.restart()

    Timer {
        interval: 500
        running: root.shown && root.playing
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
        implicitWidth: Flags.showGlyphs ? kanjiLabel.implicitWidth : 18 * root.s
        implicitHeight: Flags.showGlyphs ? kanjiLabel.implicitHeight : 18 * root.s
        opacity: skip.can ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Text {
            id: kanjiLabel
            visible: Flags.showGlyphs
            anchors.centerIn: parent
            text: skip.kanjiText
            font.family: Theme.fontJp
            font.pixelSize: 16 * root.s
            /** White like the seal so the transport reads at a glance; unavailability dims via the skip opacity. */
            color: "#ffffff"
        }

        GlyphIcon {
            visible: !Flags.showGlyphs
            anchors.centerIn: parent
            width: 17 * root.s
            height: 17 * root.s
            name: skip.icon
            /** White like the seal so the transport reads at a glance; unavailability dims via the skip opacity. */
            color: "#ffffff"
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

        /**
         * Transparent by default: the pill body is the card's background, so
         * the media view stays one continuous pill and its opacity always
         * matches the pill's. Only the legacy "wash" mode paints its own
         * background (the Rectangle below); "bleed" and "none" read through
         * to the body.
         */
        color: "transparent"

        /**
         * Legacy warm wash (Flags.mediaStyle "wash"): the original near-opaque
         * verm-tinted gradient the card shipped before the bleed, restored
         * verbatim behind everything (its baked alphas ignore the pill opacity,
         * exactly as the original did).
         */
        Rectangle {
            anchors.fill: parent
            opacity: root.washOn ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.mix(root.washMid, Theme.cardTop, 0.45), 0.92) }
                GradientStop { position: 1.0; color: Qt.alpha(root.washMid, 0.95) }
            }
        }

        /**
         * Blurred cover bleed (Flags.mediaStyle "bleed"): a tiny decode of
         * the art (already soft when upscaled) blurred through a MultiEffect
         * layer and stretched across the whole card, under the cover tile,
         * title and transport. The blur layer only exists while the card is
         * actually shown (`shown`), so it costs nothing at rest or while a
         * different surface owns the pill, and the fade rides the pill's
         * opacity like everything else.
         */
        Image {
            id: artBg

            anchors.fill: parent

            source: root.coverSource
            sourceSize: Qt.size(192, 192)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            cache: String(source).indexOf("file:") !== 0

            visible: status === Image.Ready
            opacity: root.shown && root.bleedOn ? root.artBleed : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            /** Stay blurred while the fade-out runs so the tail never snaps sharp. */
            layer.enabled: root.bleedOn && (root.shown || opacity > 0.01)
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 32
                blur: 0.7
            }
        }

        ClippingRectangle {
            id: coverBox

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16 * root.s

            width: parent.height - 32 * root.s
            height: width

            /** Tile tone follows the backdrop mode: warm-tinted under the legacy wash, standard shell tile dark otherwise, so art-less tracks still read as a cover frame. */
            radius: 16 * root.s
            color: root.tileTone

            Rectangle {
                anchors.fill: parent
                color: root.tileTone
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
                    else if (status === Image.Error)
                        root.everReady = false
                }
            }

            /** Second rung: the player's app icon when the track has no art at all. */
            Image {
                anchors.fill: parent
                anchors.margins: 12 * root.s
                source: root.appIcon
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                visible: root.artFallbackIcon && status === Image.Ready
            }

            /** Last rung: the generic music glyph, only for art-less tracks without an app icon. */
            GlyphIcon {
                anchors.centerIn: parent
                width: 40 * root.s
                height: width
                name: "music"
                color: Theme.subtle
                visible: !root.hasArt && !root.artFallbackIcon
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.textX
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.top: parent.top
        anchors.topMargin: 19 * root.s
        spacing: 3 * root.s

        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.title
            color: Theme.cream
            pixelSize: 21 * root.s
            weight: Font.DemiBold
            fadeWidth: 20 * root.s
            active: root.shown
        }

        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.artist
            color: Theme.dim
            pixelSize: 16 * root.s
            fadeWidth: 16 * root.s
            active: root.shown
            visible: text.length > 0
        }
    }

    Row {
        id: transport
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 * root.s
        spacing: 16 * root.s
        opacity: root.picking ? 0 : 1
        enabled: !root.picking
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        /**
         * The transport is right-anchored then nudged left so it sits under the
         * title/artist column; the offset is tuned to the bigger controls so the
         * row's left edge stays clear of the cover art next to it.
         */
        transform: Translate {
            x: -116 * root.s
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

            width: 36 * root.s
            height: 36 * root.s

            radius: 9 * root.s

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
                    color: Theme.mix(
                        Theme.verm,
                        Theme.tileBg,
                        0.55 - 0.27 * seal.sat
                    )
                }

                GradientStop {
                    position: 1.0
                    color: Theme.mix(
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
                font.pixelSize: 19 * root.s
                font.weight: Font.Bold
            }

            GlyphIcon {
                visible: !Flags.showGlyphs

                anchors.centerIn: parent

                width: 18 * root.s
                height: 18 * root.s

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
