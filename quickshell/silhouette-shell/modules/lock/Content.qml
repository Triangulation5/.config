pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "../../utils/format.js" as Fmt
import qs.services
import qs.components.animation
import qs.components.icons

/**
 * The lock screen's main face. Carries the profile block, the password capsule
 * with its idle "press any key" morph into the armed field, the now-playing media
 * card and progress, and the battery and link glances. The first key lands
 * straight in the input; ten seconds of silence returns the capsule to idle.
 */

Item {
    id: content
    property real s: 1.1
    property var auth: null
    property var pw: null

    property bool clockExpanded: false
    property bool revealPassword: false

    readonly property bool authenticating: auth ? auth.authenticating : false
    property bool showError: false
    property bool showCursor: false

    /**
     * The password field starts disarmed so the lock screen idles on a "press
     * any key to enter password" hint: the capsule chrome and eye are hidden and
     * only the bare prompt floats over the backdrop. Any printable key lands
     * straight in the input (the field keeps focus the whole time, so the very
     * first keystroke is captured, never swallowed), flips this on, and the
     * capsule fades back in around the text. Ten seconds without a key or click
     * while armed resets to idle again.
     */
    property bool passwordArmed: false

    /**
     * Morph progress for the capsule wake/return: 0 while the lock idles on the
     * bare hint, 1 once the field is armed. Every chrome and prompt transition
     * derives from this single value and rides the pill's own motion curve, so
     * the idle -> armed -> idle transformation is one continuous gesture in
     * both directions instead of a hard swap.
     */
    property real lockMorph: 0

    /**
     * The wake/return rides a slow, smooth ease rather than the fast
     * front-loaded morph curve, so the idle text dissolves instead of
     * snapping away and the capsule settles rather than slamming in.
     */
    Behavior on lockMorph {
        NumberAnimation {
            duration: Math.round(470 * Motion.mult)
            easing.type: Easing.InOutCubic
        }
    }

    /**
     * Fires both the slow morph and the capsule chrome's own spring (see
     * capsuleChrome), so arming inflates with an OutBack settle and
     * disarming eases back to the idle stub.
     */
    onPasswordArmedChanged: {
        lockMorph = content.passwordArmed ? 1 : 0;
        chromeSpring.from = capsuleChrome.scale;
        chromeSpring.to = content.passwordArmed ? 1.0 : 0.9;
        chromeSpring.duration = Math.round((content.passwordArmed ? 520 : 430) * Motion.mult);
        chromeSpring.easing.type = content.passwordArmed ? Easing.OutBack : Easing.InOutCubic;
        chromeSpring.easing.overshoot = 1.3;
        chromeSpring.restart();
    }

    /** Gentle InOutSine dissolve envelope for the prompt crossfade: soft at both ends. */
    function diss(t) {
        var x = Math.max(0, Math.min(1, t));
        return (1 - Math.cos(Math.PI * x)) / 2;
    }

    Shortcut {
        sequence: "Escape"

        onActivated: {
            content.clockExpanded = false;
        }
    }

    /**
     * Idle is timed, not focus-driven: 10 seconds of silence while the field is
     * armed wipes a half-typed password and returns the lock to the bare "press
     * any key" prompt. Activity while armed (typing, any key, a click) restarts
     * the countdown; authenticating pauses it so a slow auth never disarms
     * mid-flight.
     */
    Timer {
        id: idleTimer
        interval: 10000
        /**
         * Only the surface that actually holds the field's focus runs the idle
         * countdown, so silence on one monitor can never wipe a password being
         * typed on another.
         */
        running: content.passwordArmed && !content.authenticating && input.activeFocus
        onTriggered: {
            content.passwordArmed = false;
            content.showError = false;
            input.text = "";
        }
    }

    Connections {
        target: content.auth
        enabled: content.auth !== null
        function onFailed() {
            content.showError = true;
            input.text = "";
            shake.restart();
        }
        function onSucceeded() {
            content.showError = false;
            input.text = "";
        }
    }

    /**
     * The lock reads the same now-playing source as the pill's media surface and
     * OSD: the shared Players service handles proxy filtering (playerctld), DRM
     * browser fallbacks, and the manual/preferred pick, so the lock never shows a
     * different "active" player than the pill.
     */
    readonly property var player: Players.active
    readonly property bool hasPlayer: Players.has
    readonly property bool playing: Players.playing

    readonly property string trackTitle: Players.title
    readonly property string trackArtist: Players.artist
    readonly property string artUrl: Players.artUrl
    readonly property real lengthSec: Players.lengthSec
    readonly property real positionSec: hasPlayer && player ? player.position : 0
    readonly property real progress: lengthSec > 0 ? Math.max(0, Math.min(1, positionSec / lengthSec)) : 0

    readonly property string metaLine: {
        var t = lengthSec > 0 ? Fmt.fmtTime(positionSec) + " / " + Fmt.fmtTime(lengthSec) : "";
        if (trackArtist.length > 0 && t.length > 0)
            return trackArtist + " · " + t;
        return trackArtist.length > 0 ? trackArtist : t;
    }

    Timer {
        interval: 1000
        running: content.playing
        repeat: true
        onTriggered: if (content.player) content.player.positionChanged()
    }

    BatterySurface {
        id: batteryIndicator

        z: 20
        opacity: content.clockExpanded ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: parent.width * 0.055
        anchors.topMargin: parent.height * 0.065
        s: content.s
    }

    LinkSurface {
        id: linkSurface

        z: 20
        opacity: content.clockExpanded ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: parent.width * 0.055
        anchors.bottomMargin: parent.height * 0.09
        s: content.s
    }

    Clock {
        id: mainClock

        anchors.fill: parent

        s: content.s

        expanded: content.clockExpanded

        onClockClicked: {
            content.clockExpanded = !content.clockExpanded;
        }
    }

    LockPlayer {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: parent.width * 0.045
        anchors.bottomMargin: parent.height * 0.075
        s: content.s
        host: content
    }

    Rectangle {
        id: capsule
        visible: !content.clockExpanded
        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.09
        width: 340 * content.s
        height: 50 * content.s
        radius: height / 2
        /**
         * The capsule stays as the layout anchor for the prompt text and the
         * profile block; its chrome lives in capsuleChrome below so the text
         * never scales with it. While idle the chrome is gone entirely - just the
         * bare "press any key" text floating over the backdrop - and the first
         * key inflates it back in around the field.
         */
        color: "transparent"
        border.width: 0
        opacity: content.authenticating ? 0.6 : 1

        transform: Translate { id: capsuleShift }

        SequentialAnimation {
            id: shake
            NumberAnimation { target: capsuleShift; property: "x"; to: 9 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: -9 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: 6 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: -6 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: 0; duration: 50 }
        }

        /**
         * The capsule's material: fill, hairline border, and a soft drop shadow,
         * rendered behind the input. It materializes macOS-style: the chrome
         * grows up from the capsule's bottom edge as it fades in, with a gentle
         * spring puff at the midpoint (the sin term), so the idle text is handed
         * off to a formed capsule instead of a flat colour blink. The scale
         * rides lockMorph while the fill and border animate on the same curve,
         * keeping one in sync with the other.
         */
        Rectangle {
            id: capsuleChrome
            anchors.fill: parent
            radius: height / 2

            color: content.passwordArmed ? Theme.capsule : "transparent"
            border.width: content.passwordArmed ? 1 : 0
            border.color: Theme.capsuleBorder

            scale: 0.90
            transformOrigin: Item.Bottom

            /**
             * Owns the scale so arming can spring (OutBack overshoot then
             * settle) instead of puffing mid-morph; disarming eases back.
             * Fired from the root's onPasswordArmedChanged so the spring and
             * the lockMorph motion share one trigger; `from` is the live
             * value so a mid-flight reversal never jumps.
             */
            NumberAnimation {
                id: chromeSpring
                target: capsuleChrome
                property: "scale"
                duration: 520
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }

            Behavior on color {
                ColorAnimation {
                    duration: Math.round(480 * Motion.mult)
                    easing.type: Easing.InOutCubic
                }
            }

            Behavior on border.width {
                NumberAnimation {
                    duration: Math.round(480 * Motion.mult)
                    easing.type: Easing.InOutCubic
                }
            }

            layer.enabled: content.lockMorph > 0.01
            layer.smooth: true
            layer.effect: MultiEffect {
                shadowEnabled: content.lockMorph > 0.01
                shadowColor: Qt.rgba(0, 0, 0, 0.35)
                shadowBlur: 0.7
                shadowVerticalOffset: 2 * content.s
            }
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 48 * content.s
            anchors.rightMargin: 48 * content.s
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter

            echoMode: revealPassword ? TextInput.Normal : TextInput.NoEcho
            color: revealPassword ? Theme.bright : "transparent"

            font.family: Theme.font
            font.pixelSize: 15 * content.s
            font.letterSpacing: 2 * content.s
            clip: true
            focus: !content.clockExpanded
            enabled: !content.authenticating

            onTextChanged: {
                if (text.length > 0) {
                    content.showError = false;
                    content.passwordArmed = true;
                    idleTimer.restart();
                }
                if (content.pw && content.pw.text !== text)
                    content.pw.text = text;
            }

            Keys.onPressed: {
                if (content.passwordArmed)
                    idleTimer.restart();
            }

            Connections {
                target: content.pw
                enabled: content.pw !== null
                function onTextChanged() {
                    if (input.text !== content.pw.text)
                        input.text = content.pw.text;
                }
            }

            onAccepted: {
                if (content.auth && text.length > 0)
                    content.auth.submit(text);
            }

            cursorDelegate: Rectangle {
                visible: content.showCursor && input.activeFocus
                width: 2 * content.s
                height: input.cursorRectangle.height
                color: Theme.verm

                SequentialAnimation on opacity {
                    running: content.showCursor && input.activeFocus
                    loops: Animation.Infinite

                    NumberAnimation { to: 0; duration: 0 }
                    PauseAnimation { duration: 550 }
                    NumberAnimation { to: 1; duration: 0 }
                    PauseAnimation { duration: 550 }
                }
            }

            PasswordDots {
                anchors.centerIn: parent
                s: content.s
                host: content
                field: input
            }
        }

        /**
         * The idle prompts live outside the field so the input's hard clip
         * never cuts them: the widened side margins keep typed text clear of
         * the eye icon, but a clipped field would also trim the wide "press
         * any key" hint. As a capsule sibling the block centers on the pill
         * exactly where the input centers (the margins are symmetric), and it
         * only appears while the field is empty anyway.
         */
        Item {
            anchors.centerIn: parent
            visible: input.text.length === 0

            /**
             * The two prompts morph into each other on the pill's motion
             * curve: as the field arms, the idle hint scales and drifts up
             * out while "enter password" rises in from below. Returning to
             * idle plays the same morph back, so waking and settling read as
             * one continuous gesture. The soft shadow keeps whichever prompt
             * floats over the wallpaper readable, like the clock and name.
             */
            Text {
                id: idlePrompt
                anchors.centerIn: parent
                text: "<i>press any key to enter password</i>"
                textFormat: Text.RichText
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 14 * content.s
                font.letterSpacing: 1 * content.s

                visible: !content.showError
                opacity: 1 - content.diss(content.lockMorph)
                scale: 1 - 0.07 * content.diss(content.lockMorph)
                transform: Translate {
                    y: -7 * content.s * content.diss(content.lockMorph)
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.5)
                    shadowBlur: 0.7
                    shadowVerticalOffset: 1.5
                    /** macOS dissolve: the hint blurs progressively away as the capsule forms. */
                    blurEnabled: content.lockMorph > 0.01
                    blurMax: 16
                    blur: 0.5 * content.diss(content.lockMorph)
                }
            }

            Text {
                id: armedPrompt
                anchors.centerIn: parent
                text: "<i>enter password</i>"
                textFormat: Text.RichText
                color: Theme.placeholder
                font.family: Theme.font
                font.pixelSize: 14 * content.s
                font.letterSpacing: 1 * content.s

                visible: !content.showError
                opacity: content.diss(content.lockMorph)
                scale: 0.94 + 0.06 * content.diss(content.lockMorph)
                transform: Translate {
                    y: 4 * content.s * (1 - content.diss(content.lockMorph))
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.5)
                    shadowBlur: 0.7
                    shadowVerticalOffset: 1.5
                }
            }

            Text {
                id: errorPrompt
                anchors.centerIn: parent
                text: {
                    var pamMsg = content.auth ? content.auth.lastError : "";
                    return pamMsg.length > 0 ? pamMsg.toLowerCase() : "wrong password";
                }
                textFormat: Text.RichText
                color: Theme.error
                font.family: Theme.font
                font.pixelSize: 14 * content.s
                font.letterSpacing: 1 * content.s

                visible: content.showError
            }
        }

        /**
         * The typed content - password dots or revealed text - is clipped at
         * the input's side margins, and these bands dissolve its tail into
         * the capsule fill so a long password sinks past the edges instead of
         * clipping hard against them. The band color matches the chrome fill
         * exactly, so while the text is short enough to fit the bands are
         * invisible: they only appear where content passes beneath them.
         */
        Item {
            anchors.fill: input

            EdgeFade {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                fadeWidth: 30 * content.s
                fadeColor: Theme.capsule
                active: input.text.length > 0
            }

            EdgeFade {
                /** -2 margin nudges the band ~2px past the clip toward the eye, so it eats 2px less of the rightmost dots. */
                anchors.right: parent.right
                anchors.rightMargin: -2
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                fadeWidth: 30 * content.s
                fadeColor: Theme.capsule
                mirrored: true
                active: input.text.length > 0
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !content.authenticating

            onClicked: {
                content.passwordArmed = true;
                input.forceActiveFocus();
                idleTimer.restart();
            }

            z: 1
        }

        GlyphIcon {
            z: 2
            anchors.right: parent.right
            anchors.rightMargin: 16 * content.s
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * content.s
            height: 20 * content.s
            name: content.revealPassword ? "eye-off" : "eye"
            color: Theme.placeholder
            stroke: 1.8

            opacity: content.lockMorph
            visible: opacity > 0.01
            scale: 0.85 + 0.15 * content.lockMorph

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8 * content.s
                onClicked: {
                    content.passwordArmed = true;
                    input.forceActiveFocus();
                    content.revealPassword ^= true;
                    idleTimer.restart();
                }
            }
        }
    }

    Profile {
        id: profile

        s: content.s
        user: content.auth ? content.auth.user : ""

        anchors.horizontalCenter: capsule.horizontalCenter
        anchors.bottom: capsule.top
        anchors.bottomMargin: 26 * content.s

        visible: !content.clockExpanded
        opacity: content.authenticating ? 0.6 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }
}
