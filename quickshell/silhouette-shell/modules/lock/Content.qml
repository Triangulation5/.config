pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "../../utils/format.js" as Fmt
import qs.services
import qs.components.icons
import qs.components.animation
import qs.modules.lock

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
    readonly property bool lockedOut: auth ? auth.lockedOut : false
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

    Behavior on lockMorph {
        NumberAnimation {
            duration: Motion.glide
            easing.type: Motion.easeMorph
            easing.bezierCurve: Motion.morphCurve
        }
    }

    onPasswordArmedChanged: lockMorph = content.passwordArmed ? 1 : 0

    /**
     * The armed "enter password" prompt rides the same motion curve as the
     * capsule wake, but shows 100ms late every time it appears — when the
     * field arms and again when it empties out (backspace to zero) — so the
     * hint always lands just after the chrome settles. The delay comes from
     * the shared RevealLatch component (the same one the fade bands use): it
     * holds `ready` false for 100ms after the prompt becomes visible, then
     * latches, and drops the instant the prompt hides, so every appearance
     * replays the delay from zero while removal stays immediate. Its opacity
     * fades in on its own smooth curve (the morph curve is too front-loaded
     * to read as a fade), while the scale/rise still follow the capsule.
     */
    readonly property bool promptVisible: content.passwordArmed && input.text.length === 0

    RevealLatch {
        id: promptLatch
        shown: content.promptVisible
        delay: 100
    }

    /** The prompt is visible only while the field is empty, so gating on the
     * empty state replays the 100ms latch delay every time it reappears, not
     * just on the first arm. Bound through the latch's shown && ready
     * contract per the component docs: ready stays true while shown is
     * false, so hiding animates out in sync with the capsule, no delay. */
    property real armedPromptMorph: promptLatch.shown && promptLatch.ready ? 1 : 0
    property real armedPromptFade: promptLatch.shown && promptLatch.ready ? 1 : 0

    Behavior on armedPromptMorph {
        NumberAnimation {
            duration: Motion.glide
            easing.type: Motion.easeMorph
            easing.bezierCurve: Motion.morphCurve
        }
    }

    Behavior on armedPromptFade {
        NumberAnimation {
            duration: Motion.standard
            easing.type: Motion.easeStandard
        }
    }

    Shortcut {
        sequence: "Escape"

        onActivated: {
            content.clockExpanded = false;
        }
    }

    /**
     * Idle is timed, not focus-driven: an empty armed capsule waits 6 seconds,
     * while a capsule with password characters waits 10 seconds, then returns
     * to the bare "press any key" prompt. Activity while armed (typing, any key,
     * a click) restarts the countdown; authenticating pauses it so a slow auth
     * never disarms mid-flight.
     */
    Timer {
        id: idleTimer
        interval: input.text.length > 0 ? 10000 : 6000
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
        /** Once the countdown ends, drop the stale error from the 5th failure. */
        function onLockedOutChanged() {
            if (!content.lockedOut)
                content.showError = false;
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

    /**
     * AOSP-style keyguard notifications: collapsed per-app cards below the
     * date. They fade out while the clock is expanded (the surface gives the
     * floor to the date layout) and dim while auth is in flight so the capsule
     * reads as the focus; back to full when idle again.
     */
    LockNotifs {
        id: lockNotifs

        z: 15
        s: content.s

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: parent.width * 0.055
        anchors.topMargin: parent.height * 0.145

        opacity: content.clockExpanded ? 0 : (content.authenticating ? 0.4 : 1)
        enabled: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
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
         * rendered behind the input. It inflates around the prompt on the pill's
         * morph curve - growing from the centre as it fades in - so the idle text
         * is handed off to a formed capsule instead of a flat colour blink. The
         * scale rides lockMorph while the fill and border animate on the same
         * curve, keeping one in sync with the other.
         */
        Rectangle {
            id: capsuleChrome
            anchors.fill: parent
            radius: height / 2

            color: content.passwordArmed ? Theme.capsule : "transparent"
            border.width: content.passwordArmed ? 1 : 0
            border.color: Theme.capsuleBorder

            scale: 0.90 + 0.10 * content.lockMorph
            transformOrigin: Item.Center

            Behavior on color {
                ColorAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeMorph
                    easing.bezierCurve: Motion.morphCurve
                }
            }

            Behavior on border.width {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeMorph
                    easing.bezierCurve: Motion.morphCurve
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
            /** Wide insets keep the typing area a touch narrower than the capsule, clear of the curved ends and the eye icon. */
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
            enabled: !content.authenticating && !content.lockedOut

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
                /** A held Backspace clears the whole field at once after 2.5s
                 * — key auto-repeat deletes one char per tick, which would
                 * otherwise leave the serialized dot cross-fades draining long
                 * after the text is gone. Timed from the first press only, so
                 * repeat ticks can't keep resetting it. */
                if (event.key === Qt.Key_Backspace && !event.isAutoRepeat)
                    holdClear.restart();
            }

            Keys.onReleased: (event) => {
                if (event.key === Qt.Key_Backspace)
                    holdClear.stop();
            }

            /** 2.5s of continuous Backspace: wipe the field and every bead at
             * once, abandoning the serialized delete queue mid-flight. */
            Timer {
                id: holdClear
                interval: 2500
                onTriggered: {
                    input.text = "";
                    dots.clearAll();
                }
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
                id: dots
                anchors.centerIn: parent
                s: content.s
                host: content
                field: input
            }

            /**
             * The fade bands ride a RevealLatch so they appear 100ms after
             * the first character lands instead of snapping on with it - the
             * dots get a beat to settle before the dissolve shows. The latch
             * releases the instant the field empties, so removal is instant.
             * (Consumers gate on shown && ready, per the component's
             * contract: ready stays true while shown is false.)
             */
            RevealLatch {
                id: fadeLatch
                shown: content.passwordArmed && input.text.length > 0
                delay: 100
            }

            /**
             * Side fades on the input so overflowing dots (and revealed text)
             * sink into the capsule surface instead of clipping hard at the
             * field's edge. The band is the capsule fill itself, so it stays
             * invisible while the content fits and only appears where it rides
             * over the dots. The vertical insets keep the band inside the
             * capsule's rounded silhouette even while the chrome is still
             * inflating (it scales from 0.9 up on the wake morph). Gated on
             * typed text: while the field is empty the idle/armed prompts show
             * and there is nothing to fade, so the bands stay off and can never
             * brush the prompt text.
             */
            EdgeFade {
                anchors.top: parent.top
                anchors.topMargin: 7 * content.s
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7 * content.s
                anchors.left: parent.left
                fadeWidth: 16 * content.s
                fadeColor: Theme.capsule
                active: fadeLatch.shown && fadeLatch.ready
            }

            EdgeFade {
                anchors.top: parent.top
                anchors.topMargin: 7 * content.s
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7 * content.s
                anchors.right: parent.right
                anchors.rightMargin: -2 * content.s
                fadeWidth: 16 * content.s
                fadeColor: Theme.capsule
                mirrored: true
                active: fadeLatch.shown && fadeLatch.ready
            }
        }

        /**
         * The prompts live outside the clipped field on purpose: the input's
         * rectangular clip cuts at its 48·s side insets, and the idle hint is
         * wide enough to get shaved there. As a sibling of the field, the
         * prompt stack stays centered on the capsule - the same spot, since
         * the field is centered in it - but no clip can touch it, and it
         * paints above the field's fade bands.
         */
        Item {
            anchors.centerIn: capsule
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
                opacity: 1 - content.lockMorph
                scale: 1 - 0.12 * content.lockMorph
                transform: Translate {
                    y: -6 * content.s * content.lockMorph
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
                id: armedPrompt
                anchors.centerIn: parent
                text: "<i>enter password</i>"
                textFormat: Text.RichText
                color: Theme.placeholder
                font.family: Theme.font
                font.pixelSize: 14 * content.s
                font.letterSpacing: 1 * content.s

                visible: !content.showError
                opacity: content.armedPromptFade
                scale: 0.88 + 0.12 * content.armedPromptMorph
                transform: Translate {
                    y: 6 * content.s * (1 - content.armedPromptMorph)
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
                    if (content.lockedOut)
                        return "too many attempts — try again in " + content.auth.lockoutRemaining + "s";
                    var pamMsg = content.auth ? content.auth.lastError : "";
                    return pamMsg.length > 0 ? pamMsg.toLowerCase() : "wrong password";
                }
                textFormat: Text.RichText
                color: Theme.error
                font.family: Theme.font
                font.pixelSize: 14 * content.s
                font.letterSpacing: 1 * content.s

                visible: content.showError || content.lockedOut
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !content.authenticating && !content.lockedOut

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
