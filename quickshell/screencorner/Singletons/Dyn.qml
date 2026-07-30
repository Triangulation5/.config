pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wallpaper-derived palette.
 *
 * Reads the matugen-generated colors.json and exposes reactive QColor values.
 * Any FileView update automatically propagates to Theme and all surfaces.
 */
Singleton {
    readonly property color primary: adapter.primary
    readonly property color cream: adapter.cream
    readonly property color bright: adapter.bright
    readonly property color dim: adapter.dim
    readonly property color surface: adapter.surface
    readonly property color outlineVariant: adapter.outlineVariant
    readonly property color faint: adapter.faint

    FileView {
        id: colorsFile

        path: (Quickshell.env("XDG_CACHE_HOME")
               || (Quickshell.env("HOME") + "/.cache"))
              + "/ricelin/colors.json"

        blockLoading: true
        watchChanges: true
        printErrors: false

        Component.onCompleted: reload()
        onFileChanged: reload()

        JsonAdapter {
            id: adapter

            property color primary: "#f5bd6f"
            property color cream: "#e6d6cb"
            property color bright: "#fff6f0"
            property color dim: "#8a7d74"

            property color surface: "#182e3f"
            property color outlineVariant: "#386a93"
            property color faint: "#6b7176"
        }
    }
}
