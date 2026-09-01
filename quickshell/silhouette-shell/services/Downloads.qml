pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live Firefox download progress for the pill. Firefox keeps its download
 * manager state in `<profile>/downloads.json` and rewrites it when a download
 * starts or finishes, so the newest such file across every profile location
 * (the classic `~/.mozilla/firefox`, the newer `~/.config/mozilla/firefox`
 * layout, and flatpak/snap sandboxes) is watched with the same
 * FileView/watchChanges pattern the flags and calendar use.
 *
 * The file only persists a fixed set of flags (`succeeded`, `canceled`,
 * `totalBytes`, `hasPartialData`, …) — it deliberately excludes current bytes,
 * so a running download is detected from an entry that is neither succeeded,
 * canceled nor errored, and live progress is tracked separately by stat'ing
 * the file Firefox is writing: the `partFilePath` when the target is stored
 * as an object, otherwise the target path itself (modern Firefox writes in
 * place). A 1s poll reads the file's size for progress and a speed estimate
 * from the delta between reads. With no Firefox profile the service stays
 * dormant and re-probes every few seconds for one to appear.
 *
 * This is a read-only view — it cannot pause or cancel Firefox downloads —
 * so the bud is a progress indicator, not a control surface.
 */
Singleton {
    id: root

    property bool active: false
    property real progress: 0
    property real bytesLoaded: 0
    property real bytesTotal: 0
    property string fileName: ""
    property real speed: 0

    readonly property string sizeText: root.human(root.bytesTotal)
    readonly property string speedText: root.human(root.speed) + "/s"
    readonly property string pctText: root.bytesTotal > 0 ? Math.round(root.progress * 100) + "%" : ""

    function human(b) {
        if (!b || b <= 0)
            return "0 B";
        var units = ["B", "KB", "MB", "GB"];
        var i = 0;
        while (b >= 1024 && i < units.length - 1) {
            b /= 1024;
            i++;
        }
        return (i === 0 ? String(Math.round(b)) : (b >= 100 ? String(Math.round(b)) : b.toFixed(1))) + " " + units[i];
    }

    /** Watched downloads.json, the on-disk file to stat, prior size and its timestamp. */
    property var _watch: ({ path: "", target: "", last: 0, time: 0 })

    function probeProfiles() {
        if (probeProc.running)
            return;
        probeProc.running = true;
    }

    /**
     * Picks the most recently written downloads.json across every profile
     * location and profile (find prints mtime first, sorts newest on top), so
     * the active profile wins without parsing profile.ini.
     */
    Process {
        id: probeProc
        command: ["sh", "-c",
            "for d in \"$HOME/.mozilla/firefox\" \"$HOME/.config/mozilla/firefox\" \"$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox\" \"$HOME/snap/firefox/common/.mozilla/firefox\"; do "
            + "[ -d \"$d\" ] && find \"$d\" -name downloads.json -printf '%T@ %p\\n' 2>/dev/null; "
            + "done | sort -rn | head -1"]
        stdout: StdioCollector {
            function onStreamFinished() {
                var line = this.text.trim();
                var p = line.length > 0 ? line.replace(/^\S+\s+/, "") : "";
                if (p.length === 0) {
                    root.active = false;
                    root._watch.path = "";
                    return;
                }
                if (p !== root._watch.path) {
                    root._watch.path = p;
                    watcher.path = p;
                    watcher.reload();
                }
            }
        }
    }

    FileView {
        id: watcher
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse()
        onLoadFailed: {
            root.active = false;
            root.probeProfiles();
        }
    }

    /**
     * Newest download that is neither succeeded, canceled nor errored is the
     * live one; everything else leaves the bud hidden. Firefox serializes only
     * flag properties (no current bytes), so the growing on-disk file — the
     * target's partFilePath when present, otherwise the target path itself —
     * is polled by statTimer for live progress.
     */
    function parse() {
        var data;
        try {
            data = JSON.parse(watcher.text());
        } catch (e) {
            return;
        }
        var list = (data && data.list) ? data.list : [];
        var best = null;
        var bestStart = 0;
        for (var i = 0; i < list.length; i++) {
            var d = list[i];
            if (!d || d.succeeded || d.canceled || d.errorObj)
                continue;
            var t = Date.parse(d.startTime) || 0;
            if (t >= bestStart) {
                bestStart = t;
                best = d;
            }
        }
        if (!best) {
            root.active = false;
            root._watch.target = "";
            root._watch.last = 0;
            return;
        }
        var target = best.target;
        var path = typeof target === "object" && target ? target.path : target;
        var part = typeof target === "object" && target ? target.partFilePath : "";
        root._watch.target = part || path || "";
        root._watch.last = 0;
        root._watch.time = 0;
        root.bytesTotal = best.totalBytes || 0;
        root.fileName = String(path || "").replace(/\\/g, "/").split("/").pop();
        root.active = true;
    }

    /** 1s tick while a download is live: stat the growing file for size/speed. */
    Timer {
        id: statTimer
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: statProc.running = true
    }

    Process {
        id: statProc
        command: ["sh", "-c", "stat -c %s \"$1\" 2>/dev/null || echo 0", "_", root._watch.target]
        stdout: StdioCollector {
            function onStreamFinished() {
                var b = parseInt(this.text.trim(), 10);
                if (isNaN(b) || b < 0)
                    b = 0;
                root.applyBytes(b);
            }
        }
    }

    /**
     * Feeds a stat sample into progress and speed. Speed only makes sense from
     * a live delta; a stalled download (no growth for 3s) decays to 0.
     */
    function applyBytes(b) {
        var now = Date.now();
        if (now - root._watch.time > 3000)
            root.speed = 0;
        else if (root._watch.last > 0 && b >= root._watch.last && now > root._watch.time)
            root.speed = (b - root._watch.last) * 1000 / (now - root._watch.time);
        root._watch.last = b;
        root._watch.time = now;
        root.bytesLoaded = b;
        root.progress = root.bytesTotal > 0 ? Math.min(1, b / root.bytesTotal) : 0;
    }

    /**
     * Firefox removes downloads.json entirely when the list is empty, so with
     * no known file the probe re-runs often enough that a freshly started
     * download appears within a couple of ticks.
     */
    Timer {
        id: probeRetry
        interval: 4000
        repeat: true
        running: root._watch.path.length === 0
        onTriggered: root.probeProfiles()
    }

    Component.onCompleted: probeProfiles()
}
