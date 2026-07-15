pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property bool dyn: Flags.paletteMode !== "static"

    readonly property color onGlow: dyn ? Dyn.primary : "#d8647e"

    readonly property color verm:     dyn ? Qt.darker(Dyn.primary, 1.18) : "#d8647e"
    readonly property color vermLit:  dyn ? Dyn.primary : "#d8647e"
    readonly property color vermDeep: dyn ? Dyn.primaryContainer : "#d8647e"

    readonly property color cream:    dyn ? Dyn.cream : "#cdcdcd"
    readonly property color bright:   dyn ? Dyn.bright : "#cdcdcd"
    readonly property color dim:      dyn ? Dyn.dim : "#878787"

    readonly property color cardTop:  dyn ? Dyn.surfaceContainerHigh : "rgba(37,37,48,0.85)"
    readonly property color cardBot:  dyn ? Dyn.surfaceContainerLow : "rgba(37,37,48,0.85)"

    readonly property color border:   dyn ? Dyn.outlineVariant : "rgba(96,96,121,0.55)"

    readonly property color shadow: Qt.rgba(0, 0, 0, 0.55)

    readonly property color tileBg: dyn ? Dyn.surface : "rgba(20,20,21,0.85)"

    readonly property color subtle: dyn ? Dyn.subtle : "#878787"
    readonly property color faint: dyn ? Dyn.faint : "#606079"
    readonly property color iconDim: dyn ? Dyn.iconDim : "#878787"

    readonly property color hair:     Qt.alpha(cream, 0.13)
    readonly property color hairSoft: Qt.alpha(cream, 0.08)
    readonly property color sheen:    Qt.alpha(cream, 0.07)

    readonly property color vermDim: dyn ? Qt.darker(Dyn.primary, 1.5) : "#606079"
    readonly property color vermDimDeep: dyn ? Qt.darker(Dyn.primary, 2.2) : "#606079"
    readonly property color vermBurn: dyn ? Qt.darker(Dyn.primaryContainer, 1.1) : "#d8647e"

    readonly property color tickRest: dyn ? Dyn.tickRest : "#cdcdcd"

    readonly property color threadBg: Qt.alpha(cream, 0.13)

    readonly property color flameCore: dyn ? Qt.lighter(onGlow, 1.03) : "#d8647e"
    readonly property color flameGlow: dyn ? onGlow : "#d8647e"

    readonly property string flameInk:   dyn ? Dyn.primary : "#d8647e"
    readonly property string flameEmber: dyn ? Dyn.primaryContainer : "#d8647e"
    readonly property string flameBurn:  dyn ? Dyn.primaryContainer : "#d8647e"
    readonly property string flameTip:   dyn ? Dyn.onPrimaryContainer : "#cdcdcd"

    readonly property color todayWarm: dyn ? onGlow : "#f3be7c"

    readonly property color ghost: dyn ? Dyn.surfaceContainerHighest : "rgba(37,37,48,0.85)"

    readonly property color frameBg: Qt.alpha(cream, 0.055)
    readonly property color frameBorder: Qt.alpha(cream, 0.10)
    readonly property color creamMenu: Qt.alpha(cream, 0.82)

    readonly property real shadowOpacity: 0.5

    readonly property var fontFamilies: Qt.fontFamilies()
    readonly property string font: (Flags.uiFont.length > 0 && fontFamilies.indexOf(Flags.uiFont) >= 0) ? Flags.uiFont : "Inter"
    readonly property string fontJp: "Zen Kaku Gothic New"

    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }
}
