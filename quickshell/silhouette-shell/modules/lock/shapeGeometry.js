// Faithful port of the AOSP keyguard "PIN shape" entry animation
// (packages/SystemUI/res/drawable/pin_dot_shape_1..6_avd.xml, pin_dot_avd.xml,
// pin_dot_delete_avd.xml — Android 14+, still current on main / Android 17).
//
// Each shape AVD carries TWO overlaid path layers:
//   _R_G_L_0_G  the flourish (sparkle, triangle, star, circle ripple, heart,
//               rounded square) that pops in over the first 67ms and then
//               collapses (scale to 0.3–0.4 or path-morph to a small form)
//               over the next 283ms, ending hidden inside the dot;
//   _R_G_L_1_G  a second flash (flower/scallop/oval — or the dot itself for
//               shape 4) that snaps visible at 67ms and morphs into the same
//               universal dot path, which is the resting state of every bead.
//
// The exact pathData strings are lifted verbatim from those files. Every
// profile is sampled at the SAME fixed angles on the shared angular grid, so a
// morph is a per-sample lerp of two profiles — matching the AVD pathData
// tweening for these star-shaped forms. All radii are in absolute vector
// units (viewport 30x30), so sizes stay faithful: the dot is r≈8.7 and the
// largest flourish (shape 3 scallop) reaches r≈18.9.
.pragma library

/** Angular samples per profile; shared so morphs lerp radius-per-angle. */
var SAMPLES = 72;

/** AOSP vector viewport size (30dp). */
var VIEWPORT = 30;

/** Largest flourish extent (shape 3 scallop ≈ 18.94), for canvas scaling. */
var MAX_RADIUS = 19;

/** Delete: the ring left where the dot was (circle with a hole, r 5 / 3). */
var RING_OUTER = 5;
var RING_INNER = 3;

/* ------------------------------------------------------------------ *
 * Exact pathData from the AOSP AVDs (trimmed whitespace, verbatim).   *
 * ------------------------------------------------------------------ */

/** Universal settled dot: the valueTo of every flash morph. */
var DOT_PATH = "M-0.44 -8.69 C3.98,-8.69 7.56,-5.11 7.56,-0.69 C7.56,3.73 3.98,7.31 -0.44,7.31 C-4.86,7.31 -8.44,3.73 -8.44,-0.69 C-8.44,-5.11 -4.86,-8.69 -0.44,-8.69c";

/** _R_G_L_0_G flourish start paths, one per shape. */
var FLOURISH_PATHS = [
    // 1: four-point sparkle (concave star)
    "M-13.65 -3.95 C-16.31,-10.09 -10.09,-16.31 -3.95,-13.65 C-3.95,-13.65 -2.94,-13.21 -2.94,-13.21 C-1.06,-12.39 1.06,-12.39 2.94,-13.21 C2.94,-13.21 3.95,-13.65 3.95,-13.65 C10.09,-16.31 16.31,-10.09 13.65,-3.95 C13.65,-3.95 13.21,-2.94 13.21,-2.94 C12.39,-1.06 12.39,1.06 13.21,2.94 C13.21,2.94 13.65,3.95 13.65,3.95 C16.31,10.09 10.09,16.31 3.95,13.65 C3.95,13.65 2.94,13.21 2.94,13.21 C1.06,12.39 -1.06,12.39 -2.94,13.21 C-2.94,13.21 -3.95,13.65 -3.95,13.65 C-10.09,16.31 -16.31,10.09 -13.65,3.95 C-13.65,3.95 -13.21,2.94 -13.21,2.94 C-12.39,1.06 -12.39,-1.06 -13.21,-2.94 C-13.21,-2.94 -13.65,-3.95 -13.65,-3.95c",
    // 2: rounded triangle, point down
    "M12.78 7.57 C12.78,7.57 4.72,-8.55 4.72,-8.55 C2.77,-12.44 -2.77,-12.44 -4.72,-8.55 C-4.72,-8.55 -12.78,7.57 -12.78,7.57 C-15,12.01 -10.42,16.78 -5.89,14.74 C-5.89,14.74 -2.17,13.07 -2.17,13.07 C-0.79,12.45 0.79,12.45 2.17,13.07 C2.17,13.07 5.9,14.74 5.9,14.74 C10.42,16.78 15,12.01 12.78,7.57c",
    // 3: four-point star
    "M10.71 10.71 C5.92,15.5 -1.85,15.5 -6.64,10.71 C-6.64,10.71 -10.71,6.64 -10.71,6.64 C-15.5,1.85 -15.5,-5.92 -10.71,-10.71 C-5.92,-15.5 1.85,-15.5 6.64,-10.71 C6.64,-10.71 10.71,-6.64 10.71,-6.64 C15.5,-1.85 15.5,5.92 10.71,10.71c",
    // 4: circle r8 (ripple: r8 -> r15 -> r7.73)
    "M8 0 C8,-1.35 7.97,-1.94 7.41,-3.02 C6.85,-4.09 6.61,-4.79 5.66,-5.66 C4.7,-6.52 4.2,-6.97 3.15,-7.36 C2.09,-7.74 1.39,-8 0,-8 C-1.39,-8 -2.18,-7.78 -3.12,-7.37 C-4.07,-6.96 -4.67,-6.63 -5.66,-5.66 C-6.64,-4.68 -6.98,-4.1 -7.37,-3.13 C-7.78,-2.08 -8,-1.39 -8,0 C-8,1.4 -7.86,1.98 -7.47,2.87 C-7.08,3.76 -6.68,4.66 -5.66,5.66 C-4.63,6.65 -4,6.96 -3.12,7.37 C-2.25,7.78 -1.32,8 0,8 C1.32,8 1.86,7.88 2.9,7.46 C3.95,7.03 4.85,6.63 5.66,5.66 C6.46,4.69 6.78,4.45 7.29,3.29 C7.81,2.14 8,1.35 8,0c",
    // 5: heart / droplet
    "M-4.68 -13.34 C-2.59,-17.01 2.64,-17 4.72,-13.33 C4.72,-13.33 13.65,2.45 13.65,2.45 C15.72,6.11 13.11,10.66 8.94,10.65 C8.94,10.65 -8.98,10.62 -8.98,10.62 C-13.15,10.61 -15.75,6.05 -13.67,2.4 C-13.67,2.4 -4.68,-13.34 -4.68,-13.34c",
    // 6: rounded square (eight-fold symmetric)
    "M-2.82 -14.07 C-1.14,-15.29 1.14,-15.29 2.82,-14.07 C2.82,-14.07 7.73,-10.53 7.73,-10.53 C7.73,-10.53 12.58,-7 12.58,-7 C14.29,-5.76 15,-3.55 14.35,-1.54 C14.35,-1.54 12.51,4.14 12.51,4.14 C12.51,4.14 10.64,9.85 10.64,9.85 C9.99,11.84 8.14,13.19 6.05,13.19 C6.05,13.19 0,13.2 0,13.2 C0,13.2 -6.05,13.19 -6.05,13.19 C-8.14,13.19 -9.98,11.84 -10.64,9.85 C-10.64,9.85 -12.51,4.14 -12.51,4.14 C-12.51,4.14 -14.35,-1.54 -14.35,-1.54 C-15,-3.55 -14.29,-5.76 -12.58,-7 C-12.58,-7 -7.73,-10.53 -7.73,-10.53 C-7.73,-10.53 -2.82,-14.07 -2.82,-14.07c"
];

/**
 * _R_G_L_0_G morph targets for the shapes that path-morph instead of
 * scale-shrinking (2: small triangle, 5: small heart). Null = scale-based.
 */
var FLOURISH_END_PATHS = [
    null,
    "M6.12 0.21 C6.12,0.21 2.27,-4.35 2.27,-4.35 C1.34,-6.2 -1.3,-6.2 -2.23,-4.35 C-2.23,-4.35 -6.06,0.21 -6.06,0.21 C-7.12,2.33 -5.46,5.79 -4.03,6.54 C-2.28,7.45 -1.01,7.48 -1.01,7.48 C-1.01,7.48 1.05,7.48 1.05,7.48 C1.05,7.48 3.28,7.36 4.23,6.66 C4.92,6.15 7.18,2.33 6.12,0.21c",
    null,
    null,
    "M-2.99 -8.52 C-1.33,-9.83 1.52,-9.34 3.25,-8.28 C4.98,-7.22 6.77,-5.88 6.7,-2.4 C6.64,1.08 4.48,2.26 3.2,3.05 C1.92,3.83 -1.1,3.72 -3.03,2.76 C-4.97,1.79 -6.38,0.3 -6.37,-2.59 C-6.36,-5.49 -4.65,-7.2 -2.99,-8.52c",
    null
];

/** Scale-shrink targets for scale-based shapes (AOSP valueTo per shape). */
var FLOURISH_SHRINK = [0.3, null, 0.4, null, null, 0.35];

/** Circle-ripple radii for shape 4: pop r8->r15, then settle r15->r7.73. */
var RIPPLE = { a: 8, b: 15, c: 7.73 };

/** _R_G_L_1_G flash start paths (shape 4 flashes the dot itself). */
var FLASH_PATHS = [
    // 1: four-lobe flower
    "M-0.44 -12.06 C13.5,-14.63 13.5,-14.63 10.9,-0.69 C13.5,13.25 13.5,13.25 -0.44,10.53 C-14.38,13.25 -14.38,13.25 -11.86,-0.69 C-14.38,-14.63 -14.38,-14.63 -0.44,-12.06c",
    // 2: four-lobe flower (wider)
    "M-0.56 -14.03 C3.65,-13.99 14.58,7.64 11.51,10.42 C8.45,13.2 5.92,9.56 -0.46,9.61 C-6.85,9.65 -9.27,12.76 -12.33,10.46 C-15.39,8.15 -4.77,-14.07 -0.56,-14.03c",
    // 3: scallop / burst
    "M-10.2 -11.16 C-1.58,-18.94 4.25,-12.72 8.06,-8.64 C11.88,-4.57 17.93,1.89 9.39,9.74 C0.85,17.6 -5.06,11.3 -8.87,7.22 C-12.69,3.14 -18.81,-3.39 -10.2,-11.16c",
    // 4: the dot itself (revealed at 67ms, no morph)
    null,
    // 5: three-lobe flower
    "M-0.48 -12.86 C2.96,-12.87 14.59,5.93 11.98,9.12 C9.42,12.26 5.76,11.36 -0.48,11.41 C-6.72,11.45 -10.24,11.91 -12.78,9.16 C-15.4,6.32 -3.91,-12.85 -0.48,-12.86c",
    // 6: tall oval
    "M-0.46 -13.65 C3.05,-13.65 12.63,-6.57 12.9,-3.63 C12.98,-2.7 12.65,12.85 -0.46,12.85 C-13.57,12.85 -13.77,-2.84 -13.76,-3.63 C-13.72,-6.87 -3.96,-13.65 -0.46,-13.65c"
];

/* ------------------------------------------------------------------ *
 * Easing: cubic bezier pathInterpolators from the AVDs.               *
 * ------------------------------------------------------------------ */

function bezierEase(x1, y1, x2, y2) {
    var cx = 3 * x1;
    var bx = 3 * (x2 - x1) - cx;
    var ax = 1 - cx - bx;
    var cy = 3 * y1;
    var by = 3 * (y2 - y1) - cy;
    var ay = 1 - cy - by;
    function bezX(t) { return ((ax * t + bx) * t + cx) * t; }
    function bezY(t) { return ((ay * t + by) * t + cy) * t; }
    return function (u) {
        var t = u;
        for (var i = 0; i < 8; ++i) {
            var x = bezX(t) - u;
            if (Math.abs(x) < 1e-6)
                break;
            var d = (3 * ax * t + 2 * bx) * t + cx;
            if (Math.abs(d) < 1e-6)
                break;
            t -= x / d;
        }
        return bezY(t);
    };
}

/** Pop-in 0→1 (L_0 scale / L_1 fade / delete phases): c0.167,0.167 0.833,0.833. */
var EASE_POP = bezierEase(0.167, 0.167, 0.833, 0.833);
/** L_0 collapse 1→shrink: c0.7,0 0.6,1. */
var EASE_SHRINK = bezierEase(0.7, 0, 0.6, 1);
/** Flash morph easings, per shape (they vary across the six AVDs). */
var MORPH_EASE = [
    bezierEase(0.3, 0, 0.8, 1),
    bezierEase(0.3, 0, 0.833, 1),
    bezierEase(0.3, 0, 0.8, 1),
    null,
    bezierEase(0.3, 0, 0.7, 1),
    bezierEase(0.167, 0, 0.8, 1)
];
/** Shape 4 ripple: expand r8→r15 (c0.167,0 0.833,1), settle r15→r7.73 (c0.3,0 0.7,1). */
var EASE_RIPPLE_1 = bezierEase(0.167, 0, 0.833, 1);
var EASE_RIPPLE_2 = bezierEase(0.3, 0, 0.7, 1);

/* ------------------------------------------------------------------ *
 * Path parsing + radial sampling.                                      *
 * ------------------------------------------------------------------ */

/** Parse an SVG path (M, C/c, Z/z only) into a sampled polyline. */
function parsePath(data) {
    var tokens = data.match(/[a-zA-Z]|-?\d*\.?\d+(?:[eE][+-]?\d+)?/g) || [];
    var commands = [];
    var cur = null;
    for (var i = 0; i < tokens.length; ++i) {
        var t = tokens[i];
        if (/^[a-zA-Z]$/.test(t)) {
            cur = { type: t, args: [] };
            commands.push(cur);
        } else if (cur) {
            cur.args.push(parseFloat(t));
        }
    }

    var pts = [];
    var x = 0, y = 0;
    var startX = 0, startY = 0;

    function cubic(p0, c1, c2, p1) {
        var n = 12;
        for (var i = 0; i <= n; ++i) {
            var t = i / n;
            var u = 1 - t;
            pts.push([
                u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p1[0],
                u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p1[1]
            ]);
        }
    }

    for (var c = 0; c < commands.length; ++c) {
        var cmd = commands[c];
        var a = cmd.args;
        if (cmd.type === "M") {
            x = a[0]; y = a[1];
            startX = x; startY = y;
            pts.push([x, y]);
        } else if (cmd.type === "m") {
            x += a[0]; y += a[1];
            startX = x; startY = y;
            pts.push([x, y]);
        } else if (cmd.type === "C") {
            for (var j = 0; j + 5 < a.length; j += 6) {
                var p0 = [x, y];
                var p1 = [a[j + 4], a[j + 5]];
                cubic(p0, [a[j], a[j + 1]], [a[j + 2], a[j + 3]], p1);
                x = p1[0]; y = p1[1];
            }
        } else if (cmd.type === "c") {
            for (var k = 0; k + 5 < a.length; k += 6) {
                var q0 = [x, y];
                var q1 = [x + a[k + 4], y + a[k + 5]];
                cubic(q0, [x + a[k], y + a[k + 1]], [x + a[k + 2], y + a[k + 3]], q1);
                x = q1[0]; y = q1[1];
            }
        } else if (cmd.type === "Z" || cmd.type === "z") {
            // close: the polygon is treated as closed by rayRadius anyway
            x = startX; y = startY;
        }
    }
    return pts;
}

/** Distance from the origin to the polyline boundary along the given angle. */
function rayRadius(poly, ang) {
    var dx = Math.cos(ang);
    var dy = Math.sin(ang);
    var best = Infinity;
    var n = poly.length;
    for (var i = 0; i < n; ++i) {
        var p1 = poly[i];
        var p2 = poly[(i + 1) % n];
        var ex = p2[0] - p1[0];
        var ey = p2[1] - p1[1];
        var denom = ex * dy - ey * dx;
        if (Math.abs(denom) < 1e-9)
            continue;
        // u = cross(p1, e) / cross(d, e); denom here is cross(e, d) = -cross(d, e).
        var u = -(p1[0] * ey - p1[1] * ex) / denom;
        var t = -(p1[0] * dy - p1[1] * dx) / denom;
        if (t >= -1e-9 && t <= 1 + 1e-9 && u >= -1e-9 && u < best)
            best = u;
    }
    return best === Infinity ? 0 : best;
}

/** Sample a path as a radial profile (absolute vector units) at the shared grid. */
function profileOf(pathData) {
    var poly = parsePath(pathData);
    var out = [];
    for (var k = 0; k < SAMPLES; ++k) {
        var ang = 2 * Math.PI * k / SAMPLES - Math.PI / 2; // start at the top
        out.push(rayRadius(poly, ang));
    }
    return out;
}

function circleProfile(r) {
    var out = [];
    for (var i = 0; i < SAMPLES; ++i)
        out.push(r);
    return out;
}

function scaleProfile(prof, k) {
    var out = [];
    for (var i = 0; i < prof.length; ++i)
        out.push(prof[i] * k);
    return out;
}

function lerpProfile(a, b, t) {
    var out = [];
    for (var i = 0; i < a.length; ++i)
        out.push(a[i] + (b[i] - a[i]) * t);
    return out;
}

/* ------------------------------------------------------------------ *
 * The six shape specs, sampled once.                                   *
 * ------------------------------------------------------------------ */

/** The universal settled dot profile. */
var DOT = profileOf(DOT_PATH);

/**
 * One entry per AOSP shape: the flourish layer and flash layer, pre-sampled.
 *   flourish  start profile          end profile (null = scale-based)
 *   shrink    scale target (null = path-morphs or ripple)
 *   flash     flash start profile (null = dot, shape 4)
 *   morph     flash→dot easing index into MORPH_EASE
 */
var SHAPES = (function () {
    var list = [];
    for (var i = 0; i < FLOURISH_PATHS.length; ++i) {
        list.push({
            flourish: profileOf(FLOURISH_PATHS[i]),
            end: FLOURISH_END_PATHS[i] ? profileOf(FLOURISH_END_PATHS[i]) : null,
            shrink: FLOURISH_SHRINK[i],
            flash: FLASH_PATHS[i] ? profileOf(FLASH_PATHS[i]) : DOT,
            morph: MORPH_EASE[i],
            ripple: i === 3 ? RIPPLE : null
        });
    }
    return list;
})();