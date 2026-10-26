pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The shell's generated palette, read from the file the shell's own Dyn service
 * watches: `${XDG_CACHE_HOME:-$HOME/.cache}/silhouette/colors.json`, which
 * `wallcolors.py` rewrites on every wallpaper change, on every manual hue, and
 * when the Dynamic Material You options change. The app reads the file rather
 * than asking the shell for the colours because the two are separate Quickshell
 * instances — the file is the only thing they share.
 *
 * The mirrored keys are the ones this window's own Theme needs: the accent, the
 * surface ramp the rail and cards sit on, and the ink that reads on that ramp.
 * The rest of the palette stays in the shell. On a Material light scheme those
 * ink keys are dark and `light` is true, which is how Theme.qml knows to paint
 * light cards instead of its designed dark ones.
 *
 * Read-only: the app edits no colours, and nothing here is ever written.
 */
Singleton {
    id: root

    /** The accent ramp's base: the pill's highlight in dynamic and manual mode. */
    readonly property string primary: adapter.primary
    /** The pill's surface, one step above the backdrop. */
    readonly property string surface: adapter.surface
    readonly property string surfaceContainerLow: adapter.surface_container_low
    readonly property string surfaceContainer: adapter.surface_container
    readonly property string surfaceContainerHigh: adapter.surface_container_high
    readonly property string surfaceContainerHighest: adapter.surface_container_highest
    readonly property string outline: adapter.outline
    readonly property string outlineVariant: adapter.outline_variant
    /** Ink for this scheme: dark text on a light palette, light on a dark one. */
    readonly property string onSurface: adapter.on_surface
    readonly property string onSurfaceVariant: adapter.on_surface_variant
    /** The ink that reads on `primary` — toggle knobs and lit chips. */
    readonly property string onPrimary: adapter.on_primary
    /** True when matugen generated a Material light scheme. */
    readonly property bool light: adapter.light

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
            property string surface_container_low: "#211b13"
            property string surface_container: "#251f17"
            property string surface_container_high: "#302921"
            property string surface_container_highest: "#3b342b"
            property string primary: "#f5bd6f"
            property string on_primary: "#3d2e00"
            property string outline: "#9c8f80"
            property string outline_variant: "#4f4539"
            property string on_surface: "#e6d6cb"
            property string on_surface_variant: "#b9a99e"
            property bool light: false
        }
    }
}
