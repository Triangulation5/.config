import QtQuick
import QtQuick.Effects
import qs.services
import qs.components.animation
import qs.components.layout

/**
 * Washi hint bubble for pill controls. Anchored to its parent control and
 * centred on it; `placement` decides whether the bubble floats above (pointer
 * down) or below (pointer up) so chips near the pill edge never clip off-screen.
 * The host sets `show` from the control's own HoverHandler; the bubble arms
 * after a hover delay, fades in slowly and out fast.
 *
 * Game mode squares the card off, the flattening the pill's own body takes (see
 * Pill): the rounding is multiplied by a 0/1 factor that is animated over the
 * morph beat rather than switched with the flag, because game mode's switch is a
 * chip in the mixer and this bubble is the one on screen when it is flipped.
 *
 * Non-interactive by design: no MouseArea or HoverHandler lives here, so it
 * never steals pointer events from the controls or the mixer's hover tracker.
 * It is `visible: false` whenever fully faded, for the same reason.
 */
Item {
    id: root

    property real s: 1.1
    property string title: ""
    property string desc: ""
    property bool show: false
    property string placement: "above"

    /**
     * Run the title as a marquee when it is wider than `titleMaxWidth`. Off by
     * default: a pill's short tooltip never needs to scroll, and only the
     * settings window's captions opt in. The marquee carries no edge fade —
     * these bubbles already dissolve into their own surface, and a fade band
     * over the card's wash reads as a coloured smear rather than a dissolve.
     */
    property bool marquee: false
    /** Width the marqueeed title is capped to; a longer title scrolls within it. */
    property real titleMaxWidth: 240

    readonly property bool below: placement === "below"
    /** One em-unit: the title's font size, so every dimension scales with the text. */
    readonly property real em: titleText.pixelSize

    /**
     * The title's on-screen width. Unchanged when `marquee` is off, so a pill
     * tooltip still sizes exactly to its text; when it is on, a caption wider
     * than `titleMaxWidth` is capped and scrolls instead of stretching the
     * bubble past the room it has beside the cursor.
     */
    readonly property real titleWidth: root.marquee
        ? Math.min(titleText.implicitWidth, root.titleMaxWidth)
        : titleText.implicitWidth
    readonly property real pointerH: 0.5 * em
    readonly property real gap: 0.5 * em

    property bool armed: false

    width: bubble.width
    height: bubble.height + pointerH
    z: 20

    anchors.horizontalCenter: parent.horizontalCenter
    /**
     * Placed with `y` rather than with a vertical anchor: a bound `height` on an
     * anchored item is what left this one collapsed — under the `above`
     * placement the anchor machinery kept the height at a negative value, so the
     * card drew as a sliver against its own pointer. `y` gives the same two
     * positions the anchors did (`gap` below the parent, or a whole bubble plus
     * `gap` above it) with the height left to its own binding.
     */
    y: below ? parent.height + gap : -height - gap

    visible: armed || opacity > 0.01
    opacity: armed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.armed ? Motion.standard : Motion.fast } }

    Timer {
        id: delay
        interval: Math.floor(Math.random() * (500 - 470 + 1)) + 470
        onTriggered: root.armed = true
    }
    onShowChanged: {
        if (show) {
            delay.restart();
        } else {
            delay.stop();
            armed = false;
        }
    }

    CardFill {
        id: bubble
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.below ? root.pointerH : 0
        width: Math.max(root.titleWidth, descText.implicitWidth) + 2.3 * root.em
        /**
         * Sized from the two texts rather than from `column.implicitHeight`:
         * the column is centred in this card, so reading its height here closed
         * a loop through the card's own geometry — which Qt resolved by leaving
         * `height` at a negative value for the `above` placement, where the card
         * then drew as a sliver. The column's spacing is the 0.3em added below.
         */
        height: titleText.implicitHeight
                + (descText.visible ? descText.implicitHeight + 0.3 * root.em : 0)
                + 1.5 * root.em
        /**
         * Game mode squares the card off: full radius at rest, none while the
         * flag is on, reached over the morph beat rather than on the frame the
         * flag flips — the same 0/1 factor and curve the pill's body uses to
         * flatten its own corners, so the two collapse together.
         */
        property real gameFlat: Flags.gameMode ? 1 : 0

        Behavior on gameFlat {
            NumberAnimation {
                duration: Motion.morph
                easing.type: Motion.easeMorph
                easing.bezierCurve: Motion.morphCurve
            }
        }

        radius: 1.15 * root.em * (1 - gameFlat)
        border.width: 1
        border.color: Theme.frameBorder

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.45
            shadowVerticalOffset: 0.3 * root.em
        }
    }

    Column {
        id: column
        anchors.centerIn: bubble
        spacing: 0.3 * root.em

        Marquee {
            id: titleText
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.titleWidth
            text: root.title
            color: Theme.cream
            pixelSize: 10.5 * root.s
            weight: Font.DemiBold
            /**
             * A marqueeed caption is pixel-snapped, so it renders natively; a
             * pill tooltip that never scrolls keeps the smoother rendering it
             * has always had.
             */
            renderType: root.marquee ? Text.NativeRendering : Text.QtRendering
            /** No edge fade: the bubble's surface already carries the text away. */
            fadeWidth: 0
            /**
             * Only scroll while the bubble is on screen. The caption outlives
             * the hover (see Hint.leave), so without this the title would keep
             * ping-ponging, invisible, long after the pointer moved away.
             */
            active: root.visible
        }
        Text {
            id: descText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.desc.length > 0
            text: root.desc
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
        }
    }

    Canvas {
        width: 0.95 * root.em
        height: root.pointerH
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.below ? 0 : root.height - root.pointerH
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Theme.cardBot;
            ctx.beginPath();
            if (root.below) {
                ctx.moveTo(0, height);
                ctx.lineTo(width, height);
                ctx.lineTo(width / 2, 0);
            } else {
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.lineTo(width / 2, height);
            }
            ctx.closePath();
            ctx.fill();
        }
    }
}
