pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Persistent Rust fuzzy-ranking bridge (`silhouette-tools launcher-match`).
 *
 * Keeps a single lightweight stdin/stdout worker alive while a launcher is
 * active, indexing DesktopEntries once and answering each keystroke with an
 * array of ranked indices in sub-millisecond time. Falls back transparently
 * to `utils/launcher/fuzzy.js` whenever `Flags.useRustTools` is off or the
 * Rust binary is unavailable.
 */
Singleton {
    id: root

    readonly property string rustBin: Quickshell.env("HOME") + "/.config/scripts/bin/silhouette-tools"

    property bool rustUnavailable: false
    readonly property bool useRust: Flags.useRustTools && !root.rustUnavailable

    /** True while at least one launcher consumer is open. */
    property bool active: false

    /** Latest ranked indices returned by Rust for `lastSeq`. */
    property var rankedIndices: []
    property int lastSeq: 0
    property int pendingSeq: 0
    property bool hasResult: false

    property var cachedEntries: []
    property var cachedUsage: ({})
    property string cachedQuery: ""
    property bool procReady: false
    property bool indexSent: false

    Connections {
        target: Flags
        function onUseRustToolsChanged() {
            if (Flags.useRustTools)
                root.rustUnavailable = false;
        }
    }

    function sync(entries, query, usage) {
        root.cachedEntries = entries || [];
        root.cachedUsage = usage || ({});
        root.cachedQuery = query || "";
        if (!root.useRust || !root.active)
            return;
        if (!proc.running) {
            proc.running = true;
            return;
        }
        if (!root.procReady)
            return;
        sendIndexAndQuery();
    }

    function sendQuery(query) {
        root.cachedQuery = query || "";
        if (!root.useRust || !root.active)
            return;
        if (!proc.running) {
            proc.running = true;
            return;
        }
        if (!root.procReady)
            return;
        if (!root.indexSent) {
            sendIndexAndQuery();
            return;
        }
        root.pendingSeq += 1;
        proc.write(JSON.stringify({ cmd: "query", seq: root.pendingSeq, q: root.cachedQuery }) + "\n");
    }

    function sendIndexAndQuery() {
        var list = root.cachedEntries || [];
        var payload = new Array(list.length);
        for (var i = 0; i < list.length; i++) {
            var e = list[i];
            var rawKw = e && e.keywords ? e.keywords : null;
            var kwList = [];
            if (rawKw && rawKw.length) {
                for (var k = 0; k < rawKw.length; k++)
                    kwList.push(String(rawKw[k]));
            }
            payload[i] = {
                id: e && e.id ? String(e.id) : "",
                name: e && e.name ? String(e.name) : "",
                genericName: e && e.genericName ? String(e.genericName) : "",
                keywords: kwList
            };
        }
        proc.write(JSON.stringify({ cmd: "index", entries: payload }) + "\n");
        proc.write(JSON.stringify({ cmd: "usage", usage: root.cachedUsage || ({}) }) + "\n");
        root.indexSent = true;
        root.pendingSeq += 1;
        proc.write(JSON.stringify({ cmd: "query", seq: root.pendingSeq, q: root.cachedQuery }) + "\n");
    }

    /** Map the latest Rust index array back to the caller's entry objects. */
    function resolve(entries) {
        if (!root.useRust || !root.hasResult)
            return null;
        var idxs = root.rankedIndices;
        var out = new Array(idxs.length);
        var n = 0;
        for (var i = 0; i < idxs.length; i++) {
            var idx = idxs[i];
            if (idx >= 0 && idx < entries.length)
                out[n++] = entries[idx];
        }
        if (n !== out.length)
            out.length = n;
        return out;
    }

    Process {
        id: proc
        command: [root.rustBin, "launcher-match"]
        stdinEnabled: true
        running: root.active && root.useRust

        onStarted: {
            root.procReady = true;
            root.indexSent = false;
            root.hasResult = false;
            if (root.cachedEntries.length > 0)
                root.sendIndexAndQuery();
        }

        onRunningChanged: {
            if (!running) {
                root.procReady = false;
                root.indexSent = false;
                root.hasResult = false;
            }
        }

        stdout: SplitParser {
            onRead: function (line) {
                if (!line || line.trim().length === 0)
                    return;
                try {
                    var msg = JSON.parse(line);
                    if (msg && typeof msg.seq === "number" && Array.isArray(msg.indices)) {
                        if (msg.seq >= root.lastSeq) {
                            root.lastSeq = msg.seq;
                            root.rankedIndices = msg.indices;
                            root.hasResult = true;
                        }
                    }
                } catch (e) {
                }
            }
        }

        onExited: function (exitCode) {
            root.procReady = false;
            root.indexSent = false;
            root.hasResult = false;
            if (root.active && root.useRust && exitCode !== 0)
                root.rustUnavailable = true;
        }
    }
}
