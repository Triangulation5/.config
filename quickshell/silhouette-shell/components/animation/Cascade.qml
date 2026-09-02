pragma ComponentBehavior: Bound

import QtQuick

/**
 * Staggered-reveal driver for pill surfaces. One `settle` value (0 → 1) that
 * stays 0 until the host surface's morph has landed (morphCloseness > 0.92),
 * then animates to 1 over `duration` — so a surface's content never cascades
 * while the pill is still growing into it. Snap back to 0 on close, so every
 * open re-cascades.
 *
 * Two consumption styles:
 *  - `section(delay)` — a smoothstep band that stays 0 until `delay` and
 *    eases to 1 as settle finishes (weather-style: header, hours, sun, moon).
 *  - `item(i)` — per-row stagger: each index starts after a small gap and
 *    the whole list finishes by settle == 1. `count` adapts the per-row gap
 *    so a long list sweeps quickly instead of ending half-hidden.
 *
 * Bind rows' opacity (and optionally a small scale) to `item(i)` / `section()`
 * and add no Behaviors — the settle animation drives them continuously.
 */
Item {
    id: root

    visible: false

    /** Host surface's morphCloseness (0 at rest, 1 fully open). */
    property real morphCloseness: 0

    /** How long the whole cascade takes once the morph has landed (ms). */
    property int duration: 600

    /** Settle fraction before the first item starts. */
    property real first: 0.1

    /** Per-item delay as a settle fraction (compressed adaptively for long lists). */
    property real gap: 0.06

    /** Items being staggered; also compresses `gap` when the list is long. */
    property int count: 1

    /** 0 → 1 while the cascade is playing. */
    property real settle: 0

    function smoothstep(x) {
        x = Math.max(0, Math.min(1, x));
        return x * x * (3 - 2 * x);
    }

    /** Weather-style section band: 0 until `delay`, eased to 1 as settle → 1. */
    function section(delay) {
        return root.smoothstep((root.settle - delay) / Math.max(0.05, 1 - delay));
    }

    /** Per-item band: item `i` starts after `first + i·gap` and finishes by settle 1. */
    function item(i) {
        var g = Math.min(root.gap, (1 - root.first) / Math.max(1, root.count));
        var window = Math.max(0.12, 1 - root.first - (root.count - 1) * g);
        return root.smoothstep((root.settle - root.first - i * g) / window);
    }

    onMorphClosenessChanged: {
        if (root.morphCloseness > 0.92 && root.settle < 1)
            anim.restart();
        else if (root.morphCloseness < 0.05 && root.settle > 0)
            root.settle = 0;
    }

    NumberAnimation {
        id: anim
        target: root
        property: "settle"
        to: 1
        duration: root.duration
        easing.type: Easing.OutCubic
    }
}