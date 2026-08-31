pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Update backend for the 更 UPDATES sub-surface: a terminal-free face for the
 * Ricelin update engine. Never touches git itself; it shells out to the python
 * engine at ~/.config/hypr/scripts/ricelin-update.py, which prints one JSON
 * object. `check` is a safe dry-run that reports how far behind the install is,
 * the changelog, and any protected file whose local edits clash with upstream;
 * `apply` performs the update, taking upstream wholesale only for the
 * conflicting files the user explicitly opted to overwrite.
 *
 * The engine owns every policy decision (devmode detection, on-demand cloning,
 * three-way merges); this singleton is a thin reader of its contract that owns
 * the state, the processes and the user's take/dep choices. The surface renders
 * the state and nothing else.
 */
Singleton {
    id: root

    readonly property string engine: Quickshell.env("HOME") + "/.config/hypr/scripts/ricelin-update.py"

    property string status: ""
    property string version: ""
    property int behindCount: 0
    property string fromDate: ""
    property string toDate: ""
    property var changelog: []
    property var conflicts: []
    property string errorText: ""

    property bool checking: false
    property bool applying: false
    property bool restartNeeded: false

    /** Target short sha, split off the engine's "<sha> <date>" version string. */
    readonly property string targetShort: version.split(" ")[0]

    /**
     * Short sha of the installed rice, read from the engine's manifest since the
     * check result only names the target. Empty until a first apply recorded one.
     */
    property string installedShort: ""

    function readManifest() {
        try {
            root.installedShort = (JSON.parse(manifestFile.text()).syncedSha || "").slice(0, 7);
        } catch (e) {
            root.installedShort = "";
        }
    }

    /** Conflicting rel-paths the user chose to overwrite with upstream on the next apply. */
    property var takePaths: ({})

    /** Core packages this update needs that aren't installed yet: [{id, name, desc, group}]. */
    property var missingDeps: []

    /**
     * Packages the last apply couldn't bring in: [{id, error}]. A cancelled password
     * prompt, an AUR build that needs a terminal, or a repo miss all land here so a
     * failed or skipped install is never silent. Held until the next check.
     */
    property var depFailures: []

    /** Per-dep install choice, keyed by id. Absent means default ON, false means opted out. */
    property var installDeps: ({})

    /** A dep is installed on apply unless the user explicitly turned its toggle off. */
    function depChosen(id) {
        return root.installDeps[id] !== false;
    }

    readonly property bool busy: checking || applying
    readonly property bool behind: status === "ok" && behindCount > 0
    readonly property bool upToDate: status === "ok" && behindCount === 0

    readonly property string statusKind: applying ? "applying"
        : checking ? "checking"
        : restartNeeded ? "applied"
        : status === "devmode" ? "devmode"
        : status === "offline" ? "offline"
        : status === "noclone" ? "noclone"
        : status === "error" ? "error"
        : behind ? "behind"
        : upToDate ? "ok"
        : "idle"

    readonly property bool spinning: checking || applying

    function resetResult() {
        status = "";
        behindCount = 0;
        fromDate = "";
        toDate = "";
        changelog = [];
        conflicts = [];
        missingDeps = [];
        installDeps = ({});
        depFailures = [];
        errorText = "";
        takePaths = ({});
    }

    /** Drop the behind-driven sections so they vanish once an apply has landed. */
    function clearPending() {
        behindCount = 0;
        changelog = [];
        conflicts = [];
        missingDeps = [];
        installDeps = ({});
        takePaths = ({});
    }

    /**
     * The body for the post-restart toast, composed before clearPending wipes the
     * changelog. The version line confirms what landed, and the top change names
     * what is new with a count when more rode along.
     */
    function updatedBody() {
        var v = root.version.replace(" ", " · ");
        if (root.changelog.length > 0) {
            var more = root.changelog.length > 1
                ? "  (+" + (root.changelog.length - 1) + " more)" : "";
            return "Now on " + v + "\n" + root.changelog[0] + more;
        }
        return "Now on " + v;
    }

    function ingest(data) {
        root.status = data.status || "error";
        root.behindCount = data.behind || 0;
        root.fromDate = data.fromDate || "";
        root.toDate = data.toDate || "";
        root.changelog = data.changelog || [];
        root.conflicts = data.conflicts || [];
        root.missingDeps = data.missingDeps || [];
        root.depFailures = data.depFailures || [];
        root.errorText = data.error || "";
        if (data.version && data.version.length > 0)
            root.version = data.version;
        if (data.applied)
            root.restartNeeded = data.restartNeeded === true;
    }

    /**
     * Parses the engine's JSON reply and ingests it, flagging the generic
     * error on a malformed body. `hard` (the apply path) also resets the
     * previous result so a garbled apply never leaves stale state behind.
     */
    function ingestReply(text, hard) {
        try {
            root.ingest(JSON.parse(text));
        } catch (e) {
            if (hard)
                root.resetResult();
            root.status = "error";
            root.errorText = "The updater returned something unexpected.";
        }
    }

    function startCheck() {
        if (root.busy)
            return;
        root.checking = true;
        root.restartNeeded = false;
        resetResult();
        checkProc.running = true;
    }

    function startApply() {
        if (root.busy)
            return;
        root.applying = true;
        var take = [];
        for (var rel in root.takePaths)
            if (root.takePaths[rel])
                take.push(rel);
        applyProc.takeArg = take.length > 0 ? take.join(",") : "";
        var deps = [];
        for (var i = 0; i < root.missingDeps.length; i++) {
            var id = root.missingDeps[i].id;
            if (root.depChosen(id))
                deps.push(id);
        }
        applyProc.installArg = deps.length > 0 ? deps.join(",") : "";
        applyProc.running = true;
    }

    FileView {
        id: manifestFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ricelin/update.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.readManifest()
        onFileChanged: reload()
    }

    Process {
        id: checkProc
        command: ["python3", root.engine, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false;
                root.ingestReply(this.text, false);
            }
        }
    }

    Process {
        id: applyProc
        property string takeArg: ""
        property string installArg: ""
        command: {
            var c = ["python3", root.engine, "apply"];
            if (takeArg.length > 0)
                c = c.concat(["--take", takeArg]);
            if (installArg.length > 0)
                c = c.concat(["--install-deps", installArg]);
            return c;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.applying = false;
                root.ingestReply(this.text, true);
                /**
                 * Hold the auto-restart while any install failed: a restart wipes
                 * this surface, so the user would never see what didn't install. The
                 * code is already written to disk and lands on the next manual
                 * restart or check; the failure notice stays put until then.
                 */
                if (root.restartNeeded && root.depFailures.length === 0) {
                    markerProc.body = root.updatedBody();
                    markerProc.running = true;
                    root.clearPending();
                    restartTimer.start();
                }
            }
        }
    }

    /**
     * New code only takes effect once the shell reloads, so do it for the user
     * instead of asking. The brief delay lets the "Updated" line register first.
     */
    Timer {
        id: restartTimer
        interval: 1200
        onTriggered: restartProc.running = true
    }

    /**
     * Relaunch the pill on its own. setsid detaches the relaunch so it outlives the
     * instance it kills, and the guard skips a second spawn if the watchdog already
     * brought it back. Settings persist through flags.json, so it returns as it was.
     */
    Process {
        id: restartProc
        command: ["setsid", "sh", "-c",
            "qs -c pill kill; sleep 0.4; qs -c pill ipc show >/dev/null 2>&1 || qs -c pill -d"]
    }

    /**
     * Drop a one-shot marker the restarted shell reads to toast what landed, since
     * the relaunch wipes the surface before any inline confirmation can stick. The
     * body rides in as a positional arg so the value is never re-parsed by the shell.
     */
    Process {
        id: markerProc
        property string body: ""
        command: ["sh", "-c",
            "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/ricelin\"; mkdir -p \"$d\"; printf '%s' \"$1\" > \"$d/updated\"",
            "sh", body]
    }
}
