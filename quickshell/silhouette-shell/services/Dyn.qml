pragma Singleton
import QtQuick
import Quickshell
import qs.services
import Quickshell.Io

/**
 * Live wallpaper-derived palette. matugen writes a small colour JSON on every
 * wallpaper change (via wallcolors.py) and this singleton watches it, so the
 * tokens update the moment the wallpaper does. Theme reads these wholly while
 * Dynamic or Manual is live, and only for the accent group while Accented is;
 * otherwise the curated washi hex wins. Defaults are a warm fallback so a
 * missing file still yields a usable scheme. Surfaces and the accent ramp come
 * from here; text stays locked in Theme for contrast.
 */
Singleton {
    id: root

    readonly property string surface: adapter.surface
    readonly property string surfaceContainer: adapter.surface_container
    readonly property string surfaceContainerLow: adapter.surface_container_low
    readonly property string surfaceContainerHigh: adapter.surface_container_high
    readonly property string surfaceContainerHighest: adapter.surface_container_highest
    readonly property string primary: adapter.primary
    readonly property string primaryContainer: adapter.primary_container
    /**
     * Matugen's `on_primary_container` — the ink that reads on the primary
     * container. Named for what it is rather than for the generator's key: a
     * property called `on` + a capital is read as a signal handler, and this one
     * held the empty string under that name while every sibling token mirrored
     * the palette fine.
     */
    readonly property string primaryContainerInk: adapter.on_primary_container
    readonly property string outline: adapter.outline
    readonly property string outlineVariant: adapter.outline_variant
    readonly property string cream: adapter.cream
    readonly property string bright: adapter.bright
    readonly property string subtle: adapter.subtle
    readonly property string dim: adapter.dim
    readonly property string faint: adapter.faint
    readonly property string iconDim: adapter.icon_dim
    readonly property string tickRest: adapter.tick_rest
    /** True when the generated scheme is Material light rather than dark. */
    readonly property bool light: adapter.light

    /**
     * The palette options live in flags.json, which both settings surfaces
     * write. The shell only re-reads colors.json when the generator rewrites it,
     * so an option change would otherwise do nothing until the next wallpaper
     * pick. This debounce regenerates whenever one of them lands, and it is the
     * only writer of the generated palette: the pill's Appearance surface used
     * to run its own copy for Manual mode, which raced this one on a mode
     * switch. Dynamic, Accented and Manual now all route through here, so a
     * change made in the settings window applies exactly as one made in the
     * pill.
     *
     * A change while a regeneration is already running must not be lost:
     * setting `running = true` on a running Process does nothing, which used to
     * leave the palette one change behind. Queue one rerun instead, and coalesce
     * any burst into it — only the final flags matter.
     */
    property bool regenPending: false
    property string hueArg: "0"
    property string modeArg: "dark"
    property string satArg: "0.5"

    /**
     * True while the generated palette is in play — wholly on Dynamic, or only
     * through its accent group on Accented.
     */
    readonly property bool generatedLive: Flags.paletteMode === "dynamic" || Flags.paletteMode === "accented"

    function runGeneration() {
        if (Flags.paletteMode === "manual") {
            if (manualRegen.running) {
                root.regenPending = true;
                return;
            }
            root.hueArg = String(Math.round(Flags.manualHue));
            root.modeArg = Flags.manualDark ? "dark" : "light";
            root.satArg = String(Flags.manualSat);
            manualRegen.running = true;
            return;
        }
        if (!root.generatedLive)
            return;
        if (regen.running) {
            root.regenPending = true;
            return;
        }
        regen.running = true;
    }

    Timer {
        id: regenTimer
        interval: 80
        repeat: false
        onTriggered: root.runGeneration()
    }

    Process {
        id: regen
        command: ["sh", "-c",
            "f=\"${XDG_STATE_HOME:-$HOME/.local/state}/silhouette-wallpaper\"; pic=$(cat \"$f\" 2>/dev/null); [ -f \"$pic\" ] && python3 \"$HOME/.config/scripts/wallcolors.py\" \"$pic\" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1; kitty @ load-config >/dev/null 2>&1 || true"]

        onRunningChanged: {
            if (!running && root.regenPending) {
                root.regenPending = false;
                regenTimer.restart();
            }
        }
    }

    /** Manual mode: rebuild from the chosen hue instead of the wallpaper. */
    Process {
        id: manualRegen
        command: ["sh", "-c",
            "python3 \"$HOME/.config/scripts/wallcolors.py\" --hue \"$1\" \"$2\" \"$3\" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1; kitty @ load-config >/dev/null 2>&1 || true",
            "sh", root.hueArg, root.modeArg, root.satArg]

        onRunningChanged: {
            if (!running && root.regenPending) {
                root.regenPending = false;
                regenTimer.restart();
            }
        }
    }

    Connections {
        target: Flags
        function onPaletteModeChanged() {
            if (Flags.paletteMode === "dynamic" || Flags.paletteMode === "manual" || Flags.paletteMode === "accented")
                regenTimer.restart();
        }
        function onDynamicSchemeChanged() { if (root.generatedLive) regenTimer.restart(); }
        function onDynamicContrastChanged() { if (root.generatedLive) regenTimer.restart(); }
        function onDynamicModeChanged() { if (Flags.paletteMode === "dynamic") regenTimer.restart(); }
        function onDynamicPreferChanged() { if (root.generatedLive) regenTimer.restart(); }
        function onContainerSaturationChanged() { if (root.generatedLive) regenTimer.restart(); }
        function onSurfaceRoleChanged() { if (Flags.paletteMode === "dynamic") regenTimer.restart(); }
        function onManualHueChanged() { if (Flags.paletteMode === "manual") regenTimer.restart(); }
        function onManualSatChanged() { if (Flags.paletteMode === "manual") regenTimer.restart(); }
        function onManualDarkChanged() { if (Flags.paletteMode === "manual") regenTimer.restart(); }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/silhouette/colors.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string surface: "#18120b"
            property string surface_container: "#251f17"
            property string surface_container_low: "#211b13"
            property string surface_container_high: "#302921"
            property string surface_container_highest: "#3b342b"
            property string primary: "#f5bd6f"
            property string primary_container: "#633f00"
            property string on_primary_container: "#ffddb3"
            property string outline: "#9c8f80"
            property string outline_variant: "#4f4539"
            property string cream: "#e6d6cb"
            property string bright: "#fff6f0"
            property string subtle: "#b9a99e"
            property string dim: "#8a7d74"
            property string faint: "#6f635b"
            property string icon_dim: "#cdbfb4"
            property string tick_rest: "#cbb6a3"
            property bool light: false
        }
    }
}
