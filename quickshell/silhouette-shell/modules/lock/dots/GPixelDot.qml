pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services
import "shapeGeometry.js" as Shapes

/**
 * "GPixel" lock-screen password bead — a faithful port of the AOSP keyguard
 * PIN-shape entry animation (Android 14+ through main/Android 17), using the
 * exact pathData from pin_dot_shape_1..6_avd.xml via shapeGeometry.js.
 *
 * Each bead plays the two-layer flourish once when it appears: its assigned
 * flourish (sparkle, triangle, star, circle ripple, heart, or rounded square)
 * pops in over 67ms, then a second flash layer snaps visible and morphs into
 * the standard dot while the flourish collapses, hidden inside it. The entry
 * is 350ms total (67ms pop/hold + 283ms morph) with the AOSP
 * pathInterpolators; every bead rests as the identical dot. Backspacing
 * removes the bead instantly, no animation. No rotation or alpha pulsing,
 * exactly like the AVDs.
 */
Canvas {
    id: dot

    property real s: 1.1
    /** True for the newest bead (kept for symmetry with the other styles). */
    property bool last: false
    /** Which of the six AOSP flourishes this bead plays (0-5, fixed at creation). */
    property int shapeIndex: 0

    /** Flourish progress 0→1 over 350ms (linear; per-phase easing applied in paint). */
    property real t: 0

    /** AOSP phase boundary (fraction of the 350ms total). */
    readonly property real tPop: 67 / 350    // flourish pop / hold phase

    width: 26 * dot.s
    height: width
    antialiasing: true
    smooth: true

    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.55
        shadowVerticalOffset: 1
        shadowHorizontalOffset: 0
        shadowColor: Qt.rgba(0, 0, 0, 0.16)
    }

    NumberAnimation {
        id: flourishAnim
        target: dot
        property: "t"
        to: 1
        duration: 350
        easing.type: Easing.Linear
    }

    onTChanged: dot.requestPaint()
    onWidthChanged: dot.requestPaint()

    function clamp01(v) {
        return Math.min(1, Math.max(0, v));
    }

    function fillProfile(ctx, cx, cy, sc, prof, alpha) {
        ctx.beginPath();
        var n = prof.length;
        for (var k = 0; k < n; ++k) {
            var a = 2 * Math.PI * k / n - Math.PI / 2;
            var x = cx + prof[k] * Math.cos(a) * sc;
            var y = cy + prof[k] * Math.sin(a) * sc;
            if (k === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.closePath();
        ctx.globalAlpha = alpha;
        ctx.fillStyle = Theme.bright;
        ctx.fill();
        ctx.globalAlpha = 1;
    }

    onPaint: {
        var ctx = dot.getContext("2d");
        ctx.clearRect(0, 0, dot.width, dot.height);
        var cx = dot.width / 2;
        var cy = dot.height / 2;
        var sc = (dot.width / 2 - 1.2 * dot.s) / Shapes.MAX_RADIUS;

        dot.paintFlourish(ctx, cx, cy, sc);
    }

    /**
     * The entry animation: flash layer behind, flourish on top (AOSP group
     * order). At t=1 this renders the settled dot with the collapsed flourish
     * hidden inside it — the identical resting state for every bead.
     */
    function paintFlourish(ctx, cx, cy, sc) {
        var sh = Shapes.SHAPES[dot.shapeIndex % Shapes.SHAPES.length];
        var t = dot.clamp01(dot.t);
        var p1 = dot.clamp01(t / dot.tPop);
        var p2 = dot.clamp01((t - dot.tPop) / (1 - dot.tPop));

        // Flash layer: snaps visible at 67ms; shape 4 flashes the dot itself.
        if (t >= dot.tPop) {
            var flash = sh.morph
                ? Shapes.lerpProfile(sh.flash, Shapes.DOT, sh.morph(p2))
                : Shapes.DOT;
            dot.fillProfile(ctx, cx, cy, sc, flash, 1);
        }

        // Flourish layer: pops in over 67ms, then collapses (scale-shrink,
        // path-morph, or circle ripple depending on the shape).
        if (sh.ripple) {
            var R = t < dot.tPop
                ? sh.ripple.a + (sh.ripple.b - sh.ripple.a) * Shapes.EASE_RIPPLE_1(p1)
                : sh.ripple.b + (sh.ripple.c - sh.ripple.b) * Shapes.EASE_RIPPLE_2(p2);
            var popScale = t < dot.tPop ? Shapes.EASE_POP(p1) : 1;
            dot.fillProfile(ctx, cx, cy, sc, Shapes.circleProfile(R * popScale), 1);
        } else if (sh.end) {
            var s1 = t < dot.tPop ? Shapes.EASE_POP(p1) : 1;
            dot.fillProfile(ctx, cx, cy, sc,
                Shapes.scaleProfile(Shapes.lerpProfile(sh.flourish, sh.end, sh.morph(p2)), s1), 1);
        } else {
            var s2 = t < dot.tPop
                ? Shapes.EASE_POP(p1)
                : (1 - (1 - sh.shrink) * Shapes.EASE_SHRINK(p2));
            dot.fillProfile(ctx, cx, cy, sc, Shapes.scaleProfile(sh.flourish, s2), 1);
        }
    }

    Component.onCompleted: {
        dot.t = 0;
        flourishAnim.start();
    }
}