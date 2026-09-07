pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * "Pulse" lock-screen password bead: each bead wears its own tone from a small
 * palette (light red, grey, warm amber, rose) — PasswordDots cycles the tones
 * as characters are typed, so a password grows a mixed string of embers
 * instead of one uniform flame. The freshest bead burns hottest on top of
 * whatever tone it carries: a cream wick tip warming through amber over the
 * tone's lit mid. It also "breathes": a slow, repeating fade to a dim glow
 * and back, where the dim phase pulls the tip from cream toward warm amber.
 * Older beads sit solid.
 * Entrance is the same spring-to-rest machinery the other styles use. Picked
 * by PasswordDots when the LOCKSCREEN dots animation is "pulse".
 */
Rectangle {
    id: dot

    property real s: 1.1
    /** True for the newest bead: it wears the cream wick tip and breathes. */
    property bool last: false

    /**
     * Palette slot for this bead, set by PasswordDots on creation
     * (index % 4) and fixed for the bead's lifetime — deleting and
     * re-creating beads never shuffles a surviving bead's color.
     */
    property int tone: 0

    width: 9 * dot.s
    height: width
    radius: width / 2

    /** 0 at the dimmest breath, 1 at full glow — drives the tip's hue. */
    readonly property real breath: dot.last ? (dot.pulseOpacity - 0.35) / 0.65 : 1

    /** Resting crown for a tone: dusted with grey so tones stay distinguishable. */
    function toneCrown(t) {
        if (t === 1) return Theme.mix(Theme.faint, Theme.cream, 0.4);
        if (t === 2) return Theme.mix(Theme.dim, Theme.todayWarm, 0.4);
        if (t === 3) return Theme.mix(Theme.cream, Theme.vermLit, 0.45);
        return Theme.mix(Theme.dim, Theme.verm, 0.35);
    }

    /** Resting mid for a tone. */
    function toneMid(t) {
        if (t === 1) return Theme.dim;
        if (t === 2) return Theme.todayWarm;
        if (t === 3) return Theme.vermLit;
        return Theme.verm;
    }

    /** Fire-lit mid for the freshest bead: the tone's hue, brightened. */
    function toneLitMid(t) {
        if (t === 1) return Theme.cream;
        if (t === 2) return Theme.mix(Theme.todayWarm, Theme.cream, 0.4);
        if (t === 3) return Theme.mix(Theme.vermLit, Theme.cream, 0.35);
        return Theme.vermLit;
    }

    /** Deep base for a tone; amber and red tones share the ember base. */
    function toneBase(t) {
        if (t === 1) return Theme.faint;
        return Theme.vermDeep;
    }

    /**
     * Freshest: cream wick tip warming through amber over the tone's lit mid.
     * Resting: the tone's own crown-to-base gradient, undusted body.
     */
    readonly property color tipTop: dot.last ? Theme.mix(Theme.todayWarm, Theme.cream, dot.breath) : dot.toneCrown(dot.tone)
    readonly property color tipMid: dot.last ? dot.toneLitMid(dot.tone) : dot.toneMid(dot.tone)
    readonly property color tipBase: dot.toneBase(dot.tone)

    gradient: Gradient {
        GradientStop { position: 0.0; color: dot.tipTop }
        GradientStop { position: 0.55; color: dot.tipMid }
        GradientStop { position: 1.0; color: dot.tipBase }
    }

    antialiasing: true
    smooth: true

    /** Entrance seeds: start overscaled and clear, then settle down to rest. */
    property real lift: 0
    property real dotScale: 1.4
    property real dotOpacity: 0
    property real slideX: 0

    /** Breathing phase of the newest bead (1 = full glow). */
    property real pulseOpacity: 1

    opacity: dotOpacity * pulseOpacity
    scale: dotScale

    transform: Translate {
        x: dot.slideX
        y: dot.lift
    }

    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.55
        shadowVerticalOffset: 1
        shadowHorizontalOffset: 0
        shadowColor: Qt.rgba(0, 0, 0, 0.16)
    }

    Behavior on lift {
        SpringAnimation {
            spring: 4.8
            damping: 0.34
        }
    }

    Behavior on dotScale {
        SpringAnimation {
            spring: 5.5
            damping: 0.36
        }
    }

    Behavior on dotOpacity {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    Behavior on slideX {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    /** Only the freshest bead pulses, as the wick tip. */
    SequentialAnimation on pulseOpacity {
        running: dot.last
        loops: Animation.Infinite
        NumberAnimation {
            to: 0.35
            duration: 480
        }
        NumberAnimation {
            to: 1
            duration: 480
        }
    }

    /** Restore full glow the moment the bead is no longer the newest. */
    onLastChanged: {
        if (!dot.last)
            pulseOpacity = 1;
    }

    Component.onCompleted: {
        dotOpacity = 1;
        dotScale = 1;
        lift = 0;
    }
}