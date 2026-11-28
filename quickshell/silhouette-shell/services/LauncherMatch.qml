pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Persistent Rust fuzzy-ranking bridge (`silhouette-tools launcher-match`).
 *
 * Keeps a single lightweight stdin/stdout worker alive while any launcher
 * consumer is open — plus a short warm cooldown after close so repeated opens
 * pay zero process-spawn or index-serialization latency. Tracks consumers by
 * name so the pill launcher, standalone overlay, and bar dmenu never clobber
 * each other's active state, and falls back transparently to `fuzzy.js`
 * whenever `Flags.useRustTools` is off or the Rust binary is unavailable.
 */
Singleton {
    id: root

    readonly property string rustBin: Flags.rustBin

    property bool rustUnavailable: false
    /** True once the Rust worker has started cleanly; lets AppLauncher bypass bash. */
    property bool rustVerified: false
    readonly property bool useRust: Flags.useRustTools && !root.rustUnavailable

    /** Named consumer map (`{ bar: true, pill: false, ... }`). */
    property var consumers: ({})
    property bool warm: false
    readonly property bool active: {
        for (var k in root.consumers)
            if (root.consumers[k])
                return true;
        return false;
    }

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
    property bool indexDirty: true
    property bool usageDirty: true

    Connections {
        target: Flags
        function onUseRustToolsChanged() {
            if (Flags.useRustTools)
                root.rustUnavailable = false;
        }
    }

    Timer {
        id: idleTimer
        interval: 60000
        repeat: false
        onTriggered: root.warm = false
    }

    /** Register or release a named launcher consumer (`"bar"`, `"overlay"`, `"pill"`). */
    function setConsumer(name, isActive) {
        var next = Object.assign({}, root.consumers);
        if (isActive)
            next[name] = true;
        else
            delete next[name];
        root.consumers = next;
        if (root.active) {
            idleTimer.stop();
            root.warm = true;
        } else if (proc.running) {
            idleTimer.restart();
        }
    }

    function sync(entries, query, usage) {
        var nextEntries = entries || [];
        var nextUsage = usage || ({});
        if (nextEntries !== root.cachedEntries)
            root.indexDirty = true;
        if (nextUsage !== root.cachedUsage)
            root.usageDirty = true;
        root.cachedEntries = nextEntries;
        root.cachedUsage = nextUsage;
        root.cachedQuery = query || "";
        if (!root.useRust || !root.active)
            return;
        if (!proc.running) {
            root.warm = true;
            return;
        }
        if (!root.procReady)
            return;
        flushPending();
    }

    function sendQuery(query) {
        root.cachedQuery = query || "";
        if (!root.useRust || !root.active)
            return;
        if (!proc.running) {
            root.warm = true;
            return;
        }
        if (!root.procReady)
            return;
        if (!root.indexSent || root.indexDirty || root.usageDirty) {
            flushPending();
            return;
        }
        root.pendingSeq += 1;
        proc.write(JSON.stringify({ cmd: "query", seq: root.pendingSeq, q: root.cachedQuery }) + "\n");
    }

    /** Increment one app's usage count in the live worker without resending the whole map. */
    function bumpUsage(entryId) {
        if (!entryId)
            return;
        if (proc.running && root.procReady && root.indexSent)
            proc.write(JSON.stringify({ cmd: "bump", id: String(entryId) }) + "\n");
        else
            root.usageDirty = true;
    }

    function flushPending() {
        if (!root.indexSent || root.indexDirty) {
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
            root.indexSent = true;
            root.indexDirty = false;
            root.usageDirty = true;
        }
        if (root.usageDirty) {
            proc.write(JSON.stringify({ cmd: "usage", usage: root.cachedUsage || ({}) }) + "\n");
            root.usageDirty = false;
        }
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
        running: (root.active || root.warm) && root.useRust

        onStarted: {
            root.procReady = true;
            root.rustVerified = true;
            root.indexSent = false;
            root.indexDirty = true;
            root.usageDirty = true;
            root.hasResult = false;
            if (root.active && root.cachedEntries.length > 0)
                root.flushPending();
        }

        onRunningChanged: {
            if (!running) {
                root.procReady = false;
                root.indexSent = false;
                root.indexDirty = true;
                root.usageDirty = true;
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
            root.indexDirty = true;
            root.usageDirty = true;
            root.hasResult = false;
            if ((root.active || root.warm) && root.useRust && exitCode !== 0) {
                root.rustUnavailable = true;
                root.rustVerified = false;
            }
        }
    }
}
