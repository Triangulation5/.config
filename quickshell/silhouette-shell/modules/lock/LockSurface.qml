pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import qs.modules.lock
import qs.components.layout
import qs.components.effects

/**
 * One monitor's lock surface. Blurs a grab of the desktop behind a frozen sharp
 * overlay, then wipes the lock open by growing a pill-shaped mask from the pill's
 * resting spot to the full screen. Carries the glow field and the full lock
 * Content on every monitor, so the whole UI (clock, password capsule, profile)
 * is present on each screen and the auth panel can be used from any of them.
 *
 * In the minimal bar there is no pill, so there is no cutout to wipe from: the
 * lock is simply open on the frame this surface is built, its backdrop is the
 * wallpaper instead of a grab of the desktop — built in that same frame, off the
 * mirror wallpaper.sh keeps — and the frozen overlay the wipe runs against is
 * never loaded. See `instant` below.
 */

Item {
    id: surface
    property real s: 1.1
    property var auth: null
    property var pw: null
    property string screenName: ""

    /**
     * Drives the lock-open morph. A pill-shaped hole grows from the pill's resting
     * spot out to the full screen, wiping the lock open over the grabbed desktop.
     * The grow waits for the grab so it reveals onto the real desktop, the collapse
     * just runs on unlock.
     */
    property bool active: false
    property real maskP: 0

    /**
     * The minimal bar's lock: no pill, no hole, nothing to wipe. The mask is put
     * at 1 as this surface is built, so the lock is there and interactive from
     * its first frame, and both morphs are skipped — a wipe with no pill to wipe
     * from is a delay with a picture attached, and the picture is the grab that
     * `lock.sh` no longer waits for in this mode.
     */
    readonly property bool instant: Flags.barEnabled

    Component.onCompleted: if (surface.instant)
        surface.maskP = 1

    readonly property bool overlayReady: deskOverlay.status === Image.Ready
    readonly property bool shouldOpen: active && overlayReady
    onShouldOpenChanged: if (shouldOpen && !surface.instant)
        openAnim.restart()
    onActiveChanged: if (!active && !surface.instant)
        closeAnim.restart()

    readonly property string shotSource: {
        if (surface.screenName.length === 0)
            return "";
        var dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";
        return "file://" + dir + "/silhouette-lock-" + surface.screenName + ".png";
    }

    /**
     * What the minimal bar's lock opens onto: the wallpaper mirror wallpaper.sh
     * keeps in step with the picture on screen (see services/Walls.qml), falling
     * back to the singleton's own idea of the current pick for a state dir that
     * has never synced one.
     */
    readonly property string backdrop: Walls.lockWallpaper.length > 0
        ? Walls.lockWallpaper
        : Walls.current

    clip: true

    /**
     * The blurred backdrop. In the pill's lock it is the whole build cost, so it
     * loads a beat after the surface mounts: the cheap sharp overlay and the
     * clock are up first, and the hole only reveals it once the pill has grown.
     *
     * The minimal bar has no overlay to carry that first frame, so there it is
     * built synchronously, out of the mirror. An asynchronous load in that mode
     * is a hole in the screen for as long as it takes: this surface is one
     * monitor's whole lock, so the frame before the backdrop lands is a black
     * screen with a clock on it. The mirror exists to make that load cheap — it
     * is the wallpaper cut down to the size a blurred backdrop can use — which is
     * what makes loading it in the frame affordable.
     */
    Loader {
        id: blurLayer
        anchors.fill: parent
        active: true
        asynchronous: !surface.instant

        /**
         * The whole backdrop look rides flags: the blur's reach and the grade's
         * darken, saturation, vignette and grain (Lock Screen › Backdrop in the
         * settings app). The blur layer is the one heavy item here, so a change
         * to any of them rebuilds it live; the flags are read in bindings, so
         * that happens on the next file write without a shell reload.
         */
        sourceComponent: BlurredShot {
            /**
             * Normally the grabbed desktop, so the lock opens onto the screen you
             * just left. The minimal bar takes no grab — `lock.sh` skips it so the
             * lock can come up at once — so the backdrop is the wallpaper instead,
             * out of the mirror, with no capture needed to name it.
             */
            source: surface.instant
                ? (surface.backdrop.length > 0 ? "file://" + surface.backdrop : "")
                : surface.shotSource
            /** Synchronous in the minimal bar, where this is the frame the lock is
              * seen on rather than something behind an overlay. */
            immediate: surface.instant
            spread: Flags.lockBlurSpread
            darken: Flags.lockBlurDarken
            saturate: Flags.lockBlurSaturation
            vignette: Flags.lockBlurVignette
            grain: Flags.lockBlurGrain
        }
    }

    /**
     * The glow's own height is what sets how high the flame can reach: the
     * shader paints upward from this item's bottom edge and clamps at its top,
     * so 0.72 left the tallest band fading out around two-thirds of the screen.
     * 0.94 carries the full-level flame to just under the top edge while the
     * clock and profile above it stay clear of the brightest part of the fade.
     */
    GlowField {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.94
    }

    Content {
        anchors.fill: parent

        s: surface.s
        auth: surface.auth
        pw: surface.pw

        enabled: surface.maskP >= 1
    }

    /**
     * The frozen desktop grab, sharp and opaque, punched with a pill-shaped hole.
     * As the hole grows the lock wipes open; outside the hole you keep seeing your
     * own desktop, never black. Loaded synchronously so it is ready the frame the
     * lock mounts and the reveal never opens onto a blank.
     */
    Image {
        id: deskOverlay
        anchors.fill: parent
        /** Nothing to punch through in the minimal bar, so nothing to decode. */
        source: surface.instant ? "" : surface.shotSource
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        asynchronous: false
        visible: false
        layer.enabled: true
    }

    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            id: pillMask

            color: "white"
            antialiasing: !Flags.gameMode

            readonly property real pillW: Flags.lockPillW * surface.s
            readonly property real pillH: Flags.lockPillH * surface.s
            readonly property real pillY: (Flags.notchStyle ? 0 : 8 * Flags.topGap) * surface.s

            readonly property real gameFlat: Flags.gameMode ? 1 : 0

            width: Flags.gameMode ? surface.width : pillW + (surface.width - pillW) * surface.maskP
            height: pillH + (surface.height - pillH) * surface.maskP

            x: Flags.gameMode ? 0 : (surface.width - width) / 2
            y: Flags.gameMode ? 0 : pillY * (1 - surface.maskP)

            topLeftRadius: Flags.notchStyle ? 0 : (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
            topRightRadius: Flags.notchStyle ? 0 : (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
            bottomLeftRadius: (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
            bottomRightRadius: (height / 2) * (1 - surface.maskP) * (1 - gameFlat)
        }

        RoundCorner {
            visible: Flags.notchStyle

            anchors.right: pillMask.left
            anchors.top: pillMask.top
            anchors.rightMargin: -1

            size: pillMask.height / 2
            corner: RoundCorner.CornerEnum.TopRight

            color: "white"

            /**
             * Keep the ear visible through most of the opening animation,
             * then let it fade out as the pill finishes expanding.
             */
            opacity: surface.maskP < 0.8 ? 1 : (1 - surface.maskP) / 0.2

            /**
             * Slightly enlarge the ear as the pill grows to better sell
             * the liquid morph without changing the mask geometry.
             */
            scale: 1 + surface.maskP * 0.15

            antialiasing: true
            Behavior on opacity {
                NumberAnimation {
                    duration: 60
                }
            }
        }

        RoundCorner {
            visible: Flags.notchStyle

            anchors.left: pillMask.right
            anchors.top: pillMask.top
            anchors.leftMargin: -1

            size: pillMask.height / 2
            corner: RoundCorner.CornerEnum.TopLeft

            color: "white"

            /** Match the left ear's timing. */
            opacity: surface.maskP < 0.8 ? 1 : (1 - surface.maskP) / 0.2

            /** Match the left ear's subtle growth. */
            scale: 1 + surface.maskP * 0.15

            antialiasing: true
            Behavior on opacity {
                NumberAnimation {
                    duration: 60
                }
            }
        }
    }

    MultiEffect {
        anchors.fill: parent
        /** The mask pass is the wipe; the minimal bar has nothing to run it for. */
        visible: !surface.instant
        source: deskOverlay
        maskEnabled: true
        maskInverted: true
        maskSource: maskItem
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    /**
     * The open eases in and out so it grows on smoothly instead of popping, the
     * close keeps the liquid pillMorph curve that already feels right.
     */
    NumberAnimation {
        id: openAnim
        target: surface
        property: "maskP"
        to: 1
        duration: 620
        easing.type: Easing.InOutCubic
    }

    NumberAnimation {
        id: closeAnim
        target: surface
        property: "maskP"
        to: 0
        duration: 560
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }
}
