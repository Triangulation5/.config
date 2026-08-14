pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * The launcher's prefix-mode rows (AI @, command >, terminal $) stacked at one
 * spot. Only the row matching the active mode carries a title, so the others
 * collapse to zero height; `active` tells the app list where the block ends.
 */
Column {
    id: root

    property real s: 1.1
    property var host: null

    readonly property bool active: host.aiActive || host.commandActive || host.terminalActive

    PrefixRow {
        id: aiRow
        width: parent.width
        s: root.s
        glyph: "sparkles"
        title: host.aiActive ? "Ask Perplexity" : ""
        query: host.aiQuery
        hint: "↵ ask"
        onClicked: host.runAI()
    }

    PrefixRow {
        id: commandRow
        width: parent.width
        s: root.s
        glyph: "search"
        title: host.commandActive ? "Search the web" : ""
        query: host.commandQuery
        hint: "↵ search"
        onClicked: host.runWebSearch()
    }

    PrefixRow {
        id: terminalRow
        width: parent.width
        s: root.s
        glyph: "terminal"
        title: host.terminalActive ? "Run in terminal" : ""
        query: host.terminalCommand
        hint: "↵ run"
        onClicked: host.runInTerminal()
    }
}
