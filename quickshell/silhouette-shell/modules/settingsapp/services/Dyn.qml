pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The shell's generated palette, read from the file the shell's own Dyn service
 * watches: `${XDG_CACHE_HOME:-$HOME/.cache}/silhouette/colors.json`, which
 * `wallcolors.py` rewrites on every wallpaper change and on every manual hue. The
 * app reads the file rather than asking the shell for the colours because the two
 * are separate Quickshell instances — the file is the only thing they share.
 *
 * Only two keys are mirrored, and they are the two the app's theme needs: the
 * accent and the pill's body colour. A wider mirror would be a second copy of a
 * palette to keep in sync for no reason, so the rest of `Dyn` stays in the shell.
 * The defaults are the shell's own warm fallback, so a missing file still yields a
 * usable pair instead of black.
 *
 * Read-only: the app edits no colours, and nothing here is ever written.
 */
Singleton {
    id: root

    /** The accent ramp's base: the pill's highlight in dynamic and manual mode. */
    readonly property string primary: adapter.primary
    /** The pill's surface, one step above the backdrop. */
    readonly property string surfaceContainerHigh: adapter.surface_container_high

    FileView {
        id: file
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/silhouette/colors.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            // == the shell's Dyn defaults - keep in sync ==
            property string primary: "#f5bd6f"
            property string surface_container_high: "#302921"
        }
    }
}
