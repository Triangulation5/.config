pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Read-only view of the shared flags file owned by the pill.
 *
 * This singleton intentionally mirrors only the subset of values required by
 * the screencorner. It never writes to the JSON file.
 */
Singleton {
    id: root

    readonly property string paletteMode: adapter.paletteMode
    readonly property bool time12h: adapter.time12h
    readonly property real topGap: adapter.topGap
    readonly property bool gameMode: adapter.gameMode
    readonly property bool notchStyle: adapter.notchStyle

    FileView {
        id: flagsFile

        path: (Quickshell.env("XDG_STATE_HOME")
               || (Quickshell.env("HOME") + "/.local/state"))
              + "/ricelin/flags.json"

        blockLoading: true
        watchChanges: true
        printErrors: false

        Component.onCompleted: reload()
        onFileChanged: reload()

        JsonAdapter {
            id: adapter

            property string paletteMode: "static"
            property bool time12h: true
            property bool notchStyle: true
            property real topGap: notchStyle ? 0 : 0.7
            property bool gameMode: false
        }
    }
}
