pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settingsapp.services

/**
 * The shell's own config as a thing you can snapshot and put back: the tree in
 * `~/.config/quickshell/silhouette-shell` and the state it keeps beside the flags
 * (`flags.json`, the calendar's `events.json`, the chosen wallpaper), recorded
 * together in a timestamped tarball under `~/.local/state/ricelin/backups`.
 *
 * The work is a script (`utils/backup.py`, named by Paths) rather than QML: a
 * tree copy, a directory read and an extraction are all things QML has no
 * primitive for, and the command line that did them inline would be a parser of
 * its own. It is also the shape this app already drives — the Updates page runs
 * `ricelin-update.py` and reads one JSON object back — so the two pages are the
 * same kind of thing: a script that owns the hard part, and a service that reads
 * its `status` and keeps the result.
 *
 * A restore writes files the running shell already watches, so the QML
 * hot-reloads and `flags.json` is re-read as the write lands (see Store). That
 * is why nothing here restarts anything: the shell applies the restore itself,
 * and a settings window that killed the process it was drawing in would be a
 * window that vanished mid-restore.
 *
 * The list is re-read after every run instead of being patched in memory: the
 * directory is the truth, and a user can add or remove an archive by hand.
 */
Singleton {
    id: root

    readonly property string script: Paths.backupScript
    readonly property string dir: Paths.backups

    /** Saved backups, newest first: `{ name, path, bytes, created }`. */
    property var entries: []
    /** True once the directory has been read at least once. */
    property bool ready: false

    /**
     * The run in flight: "" (idle), or the script's own verb — "create",
     * "restore", "remove". The vocabulary is the script's on purpose: this is a
     * face on it, and a second set of names for the same three things is how the
     * two ends drift apart (the page says "delete" where a user reads it).
     */
    property string action: ""
    readonly property bool busy: root.action.length > 0

    /** One line about the last run that landed, for the page's status card. */
    property string message: ""
    /** Non-empty when the last run was refused; the page prints it in place of the message. */
    property string note: ""

    /** True once the run in flight has been accounted for. */
    property bool settled: false

    /** Read the directory again. Safe to call on every page open. */
    function refresh() {
        if (root.busy)
            return;
        listProc.running = true;
    }

    /** Snapshot the shell and its state into a new archive. */
    function create() {
        root.start("create", "");
    }

    /** Put an archive back over the live config. */
    function restore(name) {
        root.start("restore", name);
    }

    /** Delete one archive. */
    function remove(name) {
        root.start("remove", name);
    }

    function start(action, name) {
        if (root.busy)
            return;
        root.settled = false;
        root.note = "";
        root.message = "";
        root.action = action;
        runProc.verb = action;
        runProc.target = name;
        runProc.running = true;
    }

    /**
     * Read one run's answer. The process reports on both exits — the collector
     * when its stream closes and `onExited` if the script died before printing
     * anything — so this is guarded rather than called once: whichever lands
     * first wins, and the other is ignored.
     */
    function settle(text, code) {
        if (root.settled)
            return;
        root.settled = true;

        var data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = null;
        }

        var verb = root.action;
        root.action = "";

        if (!data || data.status === undefined) {
            root.note = code === 0
                ? "The backup script printed something unexpected."
                : "The backup script could not be run (exit " + code + ").";
            return;
        }
        if (data.status !== "ok") {
            root.note = data.error || "The backup script failed.";
            return;
        }

        root.note = "";
        if (verb === "create")
            root.message = "Saved a backup: " + root.files(data.files) + ", " + root.sizeText(data.bytes) + ".";
        else if (verb === "restore")
            root.message = "Restored " + root.files(data.files)
                + (data.flags ? "; your flags came back too." : "; no flags were in the archive.")
                + " The shell reloads as the files land.";
        else if (verb === "remove")
            root.message = "Deleted " + data.name + ".";
        else
            root.message = "";

        // The directory is the truth, and a create or a delete has just changed
        // it: re-read rather than patch the list.
        root.refreshSoon();
    }

    /** `n` files, pluralised. */
    function files(n) {
        return n + (n === 1 ? " file" : " files");
    }

    /** Bytes as "1.4 MB" / "412 kB" / "980 B". */
    function sizeText(bytes) {
        if (bytes >= 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        if (bytes >= 1024)
            return Math.round(bytes / 1024) + " kB";
        return bytes + " B";
    }

    /**
     * A run has just ended, so `busy` is about to clear and a refresh is free to
     * go out — one tick later, because `refresh` refuses while a run is in
     * flight and the list would otherwise wait for the next page open.
     */
    function refreshSoon() {
        refreshTimer.restart();
    }

    function ingestList(text, code) {
        var data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = null;
        }
        if (!data || data.status !== "ok" || data.backups === undefined) {
            root.ready = true;
            if (data && data.error)
                root.note = data.error;
            else if (code !== 0)
                root.note = "Could not read " + root.dir + ".";
            return;
        }
        root.entries = data.backups;
        root.ready = true;
    }

    Timer {
        id: refreshTimer
        interval: 1
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["python3", root.script, "--dir", root.dir, "--shell", Paths.shell, "--state", Paths.state, "list"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: root.ingestList(this.text, 0)
        }
        onExited: function (exitCode) {
            if (listOut.text.length === 0)
                root.ingestList("", exitCode);
        }
    }

    Process {
        id: runProc

        property string verb: "create"
        property string target: ""

        command: ["python3", root.script, "--dir", root.dir, "--shell", Paths.shell,
                  "--state", Paths.state, runProc.verb]
            .concat(runProc.target.length > 0 ? [runProc.target] : [])

        stdout: StdioCollector {
            id: runOut
            onStreamFinished: root.settle(this.text, 0)
        }
        onExited: function (exitCode) {
            root.settle(runOut.text, exitCode);
        }
    }

    // Nothing is read up front. The list is asked for when the page opens (the
    // view's own `Component.onCompleted`), so a shell that boots and never opens
    // this page never spawns the script at all — the same reason the Updates page
    // checks on open rather than on a timer.
}
