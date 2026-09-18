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
 * across the card over a wallpaper-derived tint, subtle and riding the
 * pill's own opacity; "wash" — the legacy near-opaque warm tint, verbatim;
 * or "none" — fully transparent, the pill body reading through like every
 * other surface. The album art
 * itself always sits in a rounded tile on the left. Right of the cover:
 * title, artist, the play/pause seal (奏/休) flanked by 前/次 skips. All
 * now-playing data comes from [[Players]].
 *
 * Two layouts live here, chosen by `compact`. The **hover bud** leaves it
 * false and keeps the large seal transport it has always worn. The
 * **dedicated surface** (SUPER+A) sets it and wears the smaller transport at
 * the card's bottom-left, with the playback brush spanning the line above it and
 * the time readout on top of that bar: a hairline that wobbles once and settles,
 * filled to the playback point and capped with the rounded painted head, and
 * this card's scrub bar —
 * press it and the track seeks, hold it and the pointer carries the head,
 * exactly like a level bar. A player that cannot seek keeps the stroke as a
 * readout.
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
     * Playback position for the brush, and the scrub state around it. `frac` is
     * what the stroke draws: the pointer's own fraction while held, otherwise
     * the player's. `commitSec` is a seek that has been sent but not yet
     * echoed back — without it the head would snap back to the 2Hz poll's
     * stale position for up to half a second after every release.
     */
    readonly property real lengthSec: Players.lengthSec
    readonly property real positionSec: hasPlayer ? player.position : 0
    readonly property real playFrac: lengthSec > 0 ? Math.max(0, Math.min(1, positionSec / lengthSec)) : 0
    property real dragFrac: 0
    property bool dragging: false
    property real commitSec: -1
    readonly property real frac: dragging ? dragFrac
                                        : (commitSec >= 0 ? Math.max(0, Math.min(1, commitSec / Math.max(1, lengthSec)))
                                                         : playFrac)
    onPositionSecChanged: if (commitSec >= 0 && Math.abs(positionSec - commitSec) <= 1.5) commitSec = -1

    /**
     * Whether the stroke can actually move the track. MPRIS makes seeking
     * optional, and a live stream has no length to seek within, so an
     * unseekable player keeps the brush as a readout instead of a control.
     */
    readonly property bool canScrub: hasPlayer && player.canSeek && player.positionSupported
                                     && lengthSec > 0 && !live

    /** Transport scale: the dedicated surface's smaller seals. */
    readonly property real tScale: compact ? 0.72 : 1

    /**
     * Where the bead docks on the dedicated surface: the painted head of the
     * brush stroke, mirroring how the battery card docks at its charge head.
     * `mapToItem` is not reactive, so the void reads are what re-evaluate it
     * across the morph, the drag and every position tick.
     */
    readonly property point seamHead: {
        void root.width;
        void root.height;
        void root.compact;
        void root.frac;
        void stroke.width;
        void stroke.drawF;
        return stroke.mapToItem(root, stroke.headX, stroke.headY);
    }

    /** Off on the hover bud, whose bead keeps the rest position it has always had. */
    ameForm: root.compact ? "seam" : "off"
    amePoint: seamHead

    /** `m:ss` for the readout, matching the lock screen's time line. */
    function fmt(sec) {
        if (!(sec > 0))
            return "0:00";
        var t = Math.floor(sec);
        var m = Math.floor(t / 60);
        var ss = t % 60;
        return m + ":" + (ss < 10 ? "0" + ss : ss);
    }

    /**
     * True while the card is actually on screen. Drives the marquees and the
     * 2Hz position poll so neither runs while the card is invisible. The host
     * supplies it: the full media surface passes its open state, and the hover
     * bud passes the pill's hover mode (the bud stays instantiated with
     * open: true even at rest, so `open` alone can't gate it). Defaults off.
     */
    property bool shown: false

    /**
     * The dedicated surface's layout: a smaller transport and the scrubable
     * playback brush. The host sets it for the full media surface
     * (`surfaceProps` in Pill.qml); the hover bud never does, so the big
     * transport stays exactly what that bud has always shown.
     */
    property bool compact: false

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
     * Wallpaper-derived tint the bleed sits on (Flags.mediaStyle "bleed"):
     * the container tone matugen pulled from the current wallpaper, read
     * straight from [[Dyn]] rather than through Theme so it follows the
     * wallpaper in both palette modes — the backdrop always matches what is
     * actually on screen and never injects the static theme's own hues into
     * someone's colours. The blurred cover floats above it, so the card
     * reads as the wallpaper glowing through the track instead of either
     * alone; with no art decoded it stands in for the bleed entirely.
     * Scales with Flags.pillOpacity for the same translucency uniformity as
     * the art layer.
     */
    readonly property color bleedTint: Dyn.primaryContainer
    readonly property real tintBleed: 0.28 * Flags.pillOpacity

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
        /** Shrinks the glyph for the dedicated surface's smaller transport. */
        property real sizeScale: 1
        signal activated()

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Flags.showGlyphs ? kanjiLabel.implicitWidth : 18 * root.s * skip.sizeScale
        implicitHeight: Flags.showGlyphs ? kanjiLabel.implicitHeight : 18 * root.s * skip.sizeScale
        opacity: skip.can ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Text {
            id: kanjiLabel
            visible: Flags.showGlyphs
            anchors.centerIn: parent
            text: skip.kanjiText
            font.family: Theme.fontJp
            font.pixelSize: 16 * root.s * skip.sizeScale
            /** White like the seal so the transport reads at a glance; unavailability dims via the skip opacity. */
            color: "#ffffff"
        }

        GlyphIcon {
            visible: !Flags.showGlyphs
            anchors.centerIn: parent
            width: 17 * root.s * skip.sizeScale
            height: 17 * root.s * skip.sizeScale
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
         * Wallpaper-derived tint base (Flags.mediaStyle "bleed"): the matugen
         * container colour for the current wallpaper at a soft alpha, under
         * the blurred cover so the backdrop always agrees with the screen
         * behind the pill. Fades with `shown` exactly like the art layer.
         */
        Rectangle {
            anchors.fill: parent
            color: root.bleedTint
            visible: root.bleedOn && opacity > 0.01
            opacity: root.shown && root.bleedOn ? root.tintBleed : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        /**
         * Blurred cover bleed (Flags.mediaStyle "bleed"): a tiny decode of
         * the art (already soft when upscaled) blurred through a MultiEffect
         * layer and stretched across the whole card, over the wallpaper tint
         * and under the cover tile, title and transport. The blur layer only
         * exists while the card is actually shown (`shown`), so it costs
         * nothing at rest or while a different surface owns the pill, and
         * the fade rides the pill's opacity like everything else.
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

        /**
         * Over the bleed the marquees carry no edge fades at all: the bands
         * would strip the wallpaper tint backdrop, and a fade retuned to it
         * still read as a coloured smear. Other backdrop modes keep the
         * marquee's palette fade, tuned for those surfaces.
         */
        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.title
            color: Theme.cream
            pixelSize: 21 * root.s
            weight: Font.DemiBold
            fadeWidth: root.bleedOn ? 0 : 20 * root.s
            active: root.shown
        }

        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.artist
            color: Theme.dim
            pixelSize: 16 * root.s
            fadeWidth: root.bleedOn ? 0 : 16 * root.s
            active: root.shown
            visible: text.length > 0
        }
    }

    Row {
        id: transport
        // The dedicated surface puts its (smaller) transport at the card's
        // bottom-left, under the title/artist column, with the brush line above
        // it; the hover bud keeps the right-anchored row and the nudge tuned to
        // the bigger controls.
        anchors.right: root.compact ? undefined : parent.right
        anchors.rightMargin: root.compact ? 0 : root.edgePad
        anchors.left: root.compact ? parent.left : undefined
        anchors.leftMargin: root.compact ? root.textX : 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (root.compact ? 12 : 24) * root.s
        spacing: 16 * root.s * root.tScale
        opacity: root.picking ? 0 : 1
        enabled: !root.picking
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        /**
         * The transport is right-anchored then nudged left so it sits under the
         * title/artist column; the offset is tuned to the bigger controls so the
         * row's left edge stays clear of the cover art next to it.
         */
        transform: Translate {
            x: root.compact ? 0 : -116 * root.s
        }

        KanjiSkip {
            kanjiText: "前"
            icon: "prev"

            sizeScale: root.tScale

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

            width: 36 * root.s * root.tScale
            height: 36 * root.s * root.tScale

            radius: 9 * root.s * root.tScale

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
                font.pixelSize: 19 * root.s * root.tScale
                font.weight: Font.Bold
            }

            GlyphIcon {
                visible: !Flags.showGlyphs

                anchors.centerIn: parent

                width: 18 * root.s * root.tScale
                height: 18 * root.s * root.tScale

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

            sizeScale: root.tScale

            can: root.hasPlayer &&
                 root.player.canGoNext

            onActivated: {
                if (root.player)
                    root.player.next()
            }
        }
    }

    /**
     * The playback brush, drawn only on the dedicated surface (`compact`): the
     * card's scrub bar. The hairline wobbles once off the left edge and settles
     * as it runs to the right; the played part is filled to the point with the
     * stroke widening into the rounded painted head at the end.
     *
     * The head is what the pointer drags. `drawF` chases `frac` with a linear
     * animation only when the change is small — playback ticking forward — so a
     * seek (or a track change) snaps the head instead of sliding it across the
     * card; `lastFrac` is what tells the two apart, latched a turn later because
     * the Behavior is evaluated before the new target lands.
     */
    Canvas {
        id: stroke

        visible: root.compact

        anchors.left: parent.left
        anchors.leftMargin: root.textX
        // Runs the full column width: the readout sits above it, not at its end.
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40 * root.s
        height: 18 * root.s

        readonly property real inset: 3 * root.s
        readonly property real usable: Math.max(1, width - 2 * inset)
        property real targetF: root.frac
        property real lastFrac: 0
        property real drawF: targetF
        readonly property real headX: inset + drawF * usable
        readonly property real headY: waveY(drawF)

        Behavior on drawF {
            enabled: Math.abs(root.frac - stroke.lastFrac) < 0.02
            NumberAnimation { duration: Motion.standard; easing.type: Easing.Linear }
        }
        onTargetFChanged: Qt.callLater(() => { stroke.lastFrac = root.frac; })

        onDrawFChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        /** The stroke's own line: a decaying wobble so the bar is not a ruler. */
        function waveY(u) {
            return height / 2 - 2.6 * Math.sin(3 * Math.PI * u) * Math.exp(-2.5 * u) * root.s;
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width <= 0 || height <= 0)
                return;

            const n = 48;
            ctx.strokeStyle = Theme.border;
            ctx.lineWidth = 2.5 * root.s;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();
            ctx.moveTo(inset, waveY(0));
            for (let i = 1; i <= n; i++)
                ctx.lineTo(inset + (i / n) * usable, waveY(i / n));
            ctx.stroke();

            if (drawF <= 0.002)
                return;

            const hTail = 2.5 * root.s;
            const hHead = 1.75 * root.s;
            const m = Math.max(2, Math.ceil(n * drawF));
            ctx.fillStyle = Theme.verm;
            ctx.beginPath();
            ctx.arc(inset, waveY(0), hTail, Math.PI / 2, 3 * Math.PI / 2);
            for (let i = 0; i <= m; i++) {
                const u = (i / m) * drawF;
                ctx.lineTo(inset + u * usable, waveY(u) - (hTail + (hHead - hTail) * (i / m)));
            }
            ctx.arc(headX, headY, hHead, -Math.PI / 2, Math.PI / 2);
            for (let i = m; i >= 0; i--) {
                const u = (i / m) * drawF;
                ctx.lineTo(inset + u * usable, waveY(u) + (hTail + (hHead - hTail) * (i / m)));
            }
            ctx.closePath();
            ctx.fill();
        }

        /**
         * The level-bar gesture: press anywhere and the head jumps there, hold
         * and it follows the pointer, release and the track seeks. `preventStealing`
         * is the guard that keeps a container from taking the drag away mid-gesture
         * (the settings sliders need it for their ScrollView; it costs nothing here
         * and makes the bar behave the same wherever it is used).
         */
        MouseArea {
            anchors.fill: parent
            // Wider and taller to grab, but only downwards: the extra room above
            // would reach into the transport's own hit areas and, being drawn
            // after them, would swallow the bottom of the play seal.
            anchors.leftMargin: -8 * root.s
            anchors.rightMargin: -8 * root.s
            anchors.bottomMargin: -6 * root.s
            enabled: root.canScrub
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            /** Pointer x to a fraction of the stroke's own span. */
            function fracAt(mx) {
                return Math.max(0, Math.min(1, (mx - 8 * root.s - stroke.inset) / stroke.usable));
            }

            onPressed: mouse => {
                root.dragFrac = fracAt(mouse.x);
                root.dragging = true;
            }
            onPositionChanged: mouse => { if (pressed) root.dragFrac = fracAt(mouse.x); }
            onCanceled: root.dragging = false
            onReleased: {
                if (root.player && root.canScrub) {
                    root.commitSec = root.dragFrac * root.lengthSec;
                    root.player.position = root.commitSec;
                }
                root.dragging = false;
            }
        }
    }

    /**
     * The brush line's time readout, dedicated surface only, sitting on top of
     * the stroke and left-aligned with its start: `0:42 / 3:45`. Tabular figures
     * so the ticking seconds cannot jitter it, and "Live" for a stream, which
     * has no end to show. It is anchored to the stroke's top edge rather than to
     * a shared line, so the bar keeps the full column width to itself and the
     * pair still reads as one block without a wrapper between them.
     */
    Text {
        id: readout

        visible: root.compact

        anchors.left: parent.left
        anchors.leftMargin: root.textX
        anchors.bottom: stroke.top
        anchors.bottomMargin: 1 * root.s

        text: root.live ? "Live"
                        : root.fmt(root.dragging ? root.dragFrac * root.lengthSec : root.positionSec)
                          + " / " + root.fmt(root.lengthSec)
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12.5 * root.s
        font.features: { "tnum": 1 }
    }
}
