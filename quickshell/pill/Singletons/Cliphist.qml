pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    readonly property int count: entries.length
    property bool pending: false

    readonly property int maxHistory: 50

    // in-memory clipboard history
    property var buffer: []

    function addEntry(text) {
        if (!text || text.length === 0)
            return;

        // dedupe consecutive entries
        if (buffer.length && buffer[0].preview === text)
            return;

        buffer.unshift({
            id: Date.now().toString(),
            preview: text,
            isImage: false,
            label: text.length > 60 ? text.slice(0, 60) + "…" : text,
            sizeLabel: "",
            thumb: ""
        });

        if (buffer.length > maxHistory)
            buffer = buffer.slice(0, maxHistory);

        entries = buffer;
    }

    function refresh() {
        // no external process, just sync view
        entries = buffer;
    }

    function copy(entry) {
        if (!entry)
            return;

        Quickshell.execDetached([
            "wl-copy"
        ], entry.preview);
    }

    function wipe() {
        buffer = [];
        entries = [];
    }

    function remove(entry) {
        if (!entry)
            return;

        var out = [];
        for (var i = 0; i < buffer.length; i++) {
            if (buffer[i].id !== entry.id)
                out.push(buffer[i]);
        }

        buffer = out;
        entries = buffer;
    }

    Process {
        id: watchProc
        command: ["wl-paste", "--watch", "printf", "%s"]
        running: true

        stdout: SplitParser {
            onRead: {
                var text = data;
                root.addEntry(text);
            }
        }

        onExited: respawn.restart()
    }

    Timer {
        id: respawn
        interval: 2000
        onTriggered: watchProc.running = true
    }

    Component.onCompleted: {
        // initialize with current clipboard
        var p = Quickshell.exec(["wl-paste"]);
        if (p && p.stdout)
            addEntry(p.stdout);
    }
}
