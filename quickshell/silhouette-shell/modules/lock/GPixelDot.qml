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
 * pathInterpolators; every bead rests as the identical dot. Deleting
 * cross-fades the dot (scale 1→0.43, then fade) into the ring from
 * pin_dot_delete_avd. No rotation or alpha pulsing, exactly like the AVDs.
 */
Canvas {
    id: dot

    property real s: 1.1
    /** True for the newest bead (kept for symmetry with the other styles). */
    property bool last: false
    /** Which of the six AOSP flourishes this bead plays (0-5, fixed at creation). */
    property int shapeIndex: 0
    /** True once the bead has been backspaced: plays the delete cross-fade. */
    property bool deleting: false

    /** Flourish progress 0→1 over 350ms (linear; per-phase easing applied in paint). */
    property real t: 0
    /** Delete progress 0→1 over 350ms. */
    property real dt: 0

    signal deleteDone()

    /** AOSP phase boundaries (fractions of the 350ms total). */
    readonly property real tPop: 67 / 350    // flourish pop / hold phase
    readonly property real dPop: 150 / 350   // delete: dot shrink phase
    readonly property real dFade: 200 / 350  // delete: fade + ring phase

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

    NumberAnimation {
        id: deleteAnim
        target: dot
        property: "dt"
        to: 1
        duration: 160 // sped up from AOSP's 350ms
        easing.type: Easing.Linear
        onFinished: dot.deleteDone()
    }

    onDeletingChanged: {
        if (dot.deleting) {
            dot.dt = 0;
            deleteAnim.restart();
        }
    }

    onTChanged: dot.requestPaint()
    onDtChanged: dot.requestPaint()
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

        if (dot.deleting) {
            dot.paintDelete(ctx, cx, cy, sc);
            return;
        }
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

    /** pin_dot_delete_avd: dot 1→0.43 (150ms), then fade while a ring grows. */
    function paintDelete(ctx, cx, cy, sc) {
        var d = dot.clamp01(dot.dt);
        var p1 = dot.clamp01(d / dot.dPop);
        var p2 = dot.clamp01((d - dot.dPop) / dot.dFade);

        var ds = 1 - (1 - 0.43) * Shapes.EASE_POP(p1);
        var da = 1 - Shapes.EASE_POP(p2);
        dot.fillProfile(ctx, cx, cy, sc, Shapes.scaleProfile(Shapes.DOT, ds), da);

        // The ring left where the dot was: even-odd donut, scales 0.65→1.
        var rs = 0.65 + 0.35 * Shapes.EASE_POP(p2);
        ctx.beginPath();
        ctx.arc(cx, cy, Shapes.RING_OUTER * rs * sc, 0, 2 * Math.PI, false);
        ctx.arc(cx, cy, Shapes.RING_INNER * rs * sc, 0, 2 * Math.PI, false);
        ctx.fillStyle = Theme.bright;
        ctx.fill("evenodd");
    }

    Component.onCompleted: {
        dot.t = 0;
        flourishAnim.start();
    }
}