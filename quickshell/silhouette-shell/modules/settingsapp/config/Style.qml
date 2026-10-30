pragma Singleton
import QtQuick
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services
import "../../../utils/settings/style.js" as Spec

/**
 * The settings window's view of the design-language tokens.
 *
 * It reads the same profile table as the shell's `services/Style.qml` through
 * `Store.adapter.style`, and exposes the same shape, material and motion
 * numbers. The two files cannot share a runtime singleton (the app's palette is
 * mirrored from the same flags file for the same reason), so the numbers come
 * from one table and only the colour application is repeated: the shell's
 * version can read `ColorScheme`, while this one is handed the app's own
 * `accent` by `Theme.qml`.
 *
 * Material generates the same tonal container ladder as the shell: a static
 * palette has no M3 surface tokens of its own, so they are derived from the
 * accent's hue at a capped chroma. A dynamic palette already publishes a proper
 * ramp, and is passed through untouched.
 *
 * Washi is the identity profile: every helper returns its input and every
 * radius/duration is the value the panel shipped with.
 */
QtObject {
    id: root

    readonly property var p: Spec.profile(Store.adapter.style)

    readonly property string name: p.name
    readonly property bool glass: p.glass
    readonly property bool tonal: p.tonal

    /** True while the app is showing the generated palette. */
    readonly property bool dynamic: Store.adapter.paletteMode === "dynamic"
        || Store.adapter.paletteMode === "manual"

    readonly property real radiusCard: p.radiusCard
    readonly property real radiusRow: p.radiusRow
    readonly property real radiusChip: p.radiusChip
    readonly property real radiusField: p.radiusField
    readonly property real radiusTile: p.radiusTile
    readonly property real radiusSmall: p.radiusSmall

    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 24
    readonly property int space6: 32

    readonly property int animFast: p.appFast
    readonly property int animNormal: p.appNormal
    readonly property int animWindow: p.appWindow

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1);
    }

    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    /** One rung of the generated M3 neutral ladder. */
    function tone(accent, lightness) {
        var hue = accent.hslHue < 0 ? 0 : accent.hslHue;
        var chroma = Math.max(0, Math.min(accent.hslSaturation, root.p.chromaCap));
        return Qt.hsla(hue, chroma, lightness, 1);
    }

    /** The M3 outline role, used for quiet borders and dividers. */
    function outlineColor(accent) {
        var hue = accent.hslHue < 0 ? 0 : accent.hslHue;
        var chroma = Math.max(0, Math.min(accent.hslSaturation, root.p.chromaCap));
        return Qt.hsla(hue, chroma * 0.65, (root.dynamic && Dyn.light) ? 0.52 : 0.44, 1);
    }

    /** A window/card surface in the current style. */
    function surface(base, accent, kind) {
        if (root.p.glass) {
            var lighten = kind === "card" ? 0.08 : 0.05;
            var tinted = root.mix(base, Qt.rgba(1, 1, 1, 1), lighten);
            var alpha = kind === "window" ? root.p.glassAlphaWindow
                : (kind === "card" ? root.p.glassAlphaCard : root.p.glassAlpha);
            if (root.luminance(tinted) < 0.42)
                alpha = Math.min(0.82, alpha + 0.06);
            return Qt.rgba(tinted.r, tinted.g, tinted.b, alpha);
        }
        if (root.p.tonal) {
            /** Dynamic already hands us the generated M3 ramp. */
            if (root.dynamic)
                return base;
            switch (kind) {
            case "window": return root.tone(accent, 0.075);
            case "card": return root.tone(accent, 0.10);
            case "tile": return root.tone(accent, 0.145);
            case "high": return root.tone(accent, 0.135);
            case "highest": return root.tone(accent, 0.17);
            }
            return root.tone(accent, 0.10);
        }
        return base;
    }

    /** A surface outline. Material uses a quiet neutral, not an accent line. */
    function border(base, accent) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, root.p.borderRim);
        if (root.p.tonal) {
            var o = root.outlineColor(accent);
            return Qt.rgba(o.r, o.g, o.b, 0.38);
        }
        return base;
    }

    /** A small control fill: search field, nav button, segmented chip. */
    function control(base, accent) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, 0.09);
        if (root.p.tonal)
            return root.dynamic ? base : root.tone(accent, 0.145);
        return base;
    }

    /** A hover/selection wash. `strong` is the selected state. */
    function overlay(base, accent, strong) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, strong ? 0.14 : 0.07);
        if (root.p.tonal)
            return Qt.rgba(accent.r, accent.g, accent.b,
                           strong ? root.p.stateSelected : root.p.stateHover);
        return base;
    }

    /** Glass specular overlay alpha, used by the window's light layer. */
    readonly property real specularAlpha: root.p.specular
}
