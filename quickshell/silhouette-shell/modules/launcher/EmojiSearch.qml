pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "../../utils/launcher/emojis.js" as EmojiData

/**
 * Emoji search controller for the launcher (`:` prefix mode).
 * Runs the Rust `emoji-match` watcher when `Flags.useRustTools` is enabled and
 * falls back transparently to substring matching over `emojis.js`.
 */
QtObject {
    id: root

    property bool active: false
    property string query: ""
    property bool copied: false

    readonly property string watcherRunner: Qt.resolvedUrl("../../utils/watchers/run.sh").toString().replace(/^file:\/\//, "")
    readonly property string emojiDbPath: Qt.resolvedUrl("../../utils/launcher/emojis.js").toString().replace(/^file:\/\//, "")
    property bool rustUnavailable: false
    readonly property bool useRust: Flags.useRustTools && !root.rustUnavailable
    property var rustIndices: []
    property int rustSeq: 0
    property int rustPendingSeq: 0
    property bool rustReady: false
    property bool rustHasResult: false

    onQueryChanged: {
        root.copied = false;
        if (root.active && root.useRust && root.rustReady) {
            root.rustPendingSeq += 1;
            emojiMatchProc.write(root.rustPendingSeq + "\t" + root.query + "\n");
        }
    }

    readonly property var _proc: Process {
        id: emojiMatchProc
        command: [root.watcherRunner, "emoji-match", root.emojiDbPath]
        stdinEnabled: true
        running: root.active && root.useRust
        onStarted: {
            root.rustReady = true;
            root.rustHasResult = false;
            root.rustPendingSeq += 1;
            emojiMatchProc.write(root.rustPendingSeq + "\t" + root.query + "\n");
        }
        onRunningChanged: {
            if (!running) {
                root.rustReady = false;
                root.rustHasResult = false;
            }
        }
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim().length === 0)
                    return;
                try {
                    var msg = JSON.parse(line);
                    if (msg && typeof msg.seq === "number" && Array.isArray(msg.indices)) {
                        if (msg.seq >= root.rustSeq) {
                            root.rustSeq = msg.seq;
                            root.rustIndices = msg.indices;
                            root.rustHasResult = true;
                        }
                    }
                } catch (e) {
                }
            }
        }
        onExited: function(exitCode) {
            if (exitCode === 127)
                root.rustUnavailable = true;
        }
    }

    readonly property var results: {
        var q = root.query.toLowerCase();
        if (q.length === 0)
            return EmojiData.Emojis;
        if (root.useRust && root.rustHasResult) {
            var idxs = root.rustIndices;
            var mapped = new Array(idxs.length);
            var n = 0;
            for (var r = 0; r < idxs.length; r++) {
                var idx = idxs[r];
                if (idx >= 0 && idx < EmojiData.Emojis.length)
                    mapped[n++] = EmojiData.Emojis[idx];
            }
            if (n !== mapped.length)
                mapped.length = n;
            return mapped;
        }
        var out = [];
        for (var i = 0; i < EmojiData.Emojis.length; i++) {
            if (EmojiData.Emojis[i].n.indexOf(q) !== -1)
                out.push(EmojiData.Emojis[i]);
        }
        return out;
    }

    function copyAt(index) {
        if (!root.active || root.results.length === 0 || index < 0 || index >= root.results.length)
            return false;
        Quickshell.execDetached(["wl-copy", "--", root.results[index].e]);
        root.copied = true;
        return true;
    }
}
