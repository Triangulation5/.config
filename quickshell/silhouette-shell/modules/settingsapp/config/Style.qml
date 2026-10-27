pragma Singleton
import QtQuick
import qs.modules.settingsapp.config
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
 * Washi is the identity profile: every helper returns its input and every
 * radius/duration is the value the panel shipped with.
 */
QtObject {
    id: root

    readonly property var p: Spec.profile(Store.adapter.style)

    readonly property string name: p.name
    readonly property bool glass: p.glass
    readonly property bool tonal: p.tonal

    readonly property real radiusCard: p.radiusCard
    readonly property real radiusRow: p.radiusRow
    readonly property real radiusChip: p.radiusChip
    readonly property real radiusField: p.radiusField
    readonly property real radiusTile: p.radiusTile

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
            var amount = kind === "card" ? root.p.accentMixCard
                : (kind === "tile" ? root.p.accentMixTile : root.p.accentMixSurface);
            return root.mix(base, accent, amount);
        }
        return base;
    }

    /** A surface outline. */
    function border(base, accent) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, root.p.borderRim);
        if (root.p.tonal)
            return Qt.rgba(accent.r, accent.g, accent.b, root.p.borderAccent);
        return base;
    }

    /** A small control fill: search field, nav button, segmented chip. */
    function control(base, accent) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, 0.09);
        if (root.p.tonal)
            return root.mix(base, accent, 0.10);
        return base;
    }

    /** A hover/selection wash. `strong` is the selected state. */
    function overlay(base, accent, strong) {
        if (root.p.glass)
            return Qt.rgba(1, 1, 1, strong ? 0.14 : 0.07);
        if (root.p.tonal)
            return Qt.rgba(accent.r, accent.g, accent.b, strong ? 0.18 : 0.09);
        return base;
    }

    /** Glass specular overlay alpha, used by the window's light layer. */
    readonly property real specularAlpha: root.p.specular
}
