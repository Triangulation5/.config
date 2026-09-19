pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settingsapp.services

/**
 * The updater behind the Updates page: a terminal-free face for the config's own
 * script, which is never touched here — it is run and its JSON is read.
 *
 * Two updaters live in scripts/. This page drives the one about the
 * distribution's packages — `check` reports how many updates dnf has, `apply`
 * (or `apply-minimal`) runs the upgrade under pkexec and reports each command
 * and whether a reboot is wanted. That is the only thing on this machine that
 * can truthfully answer "what updates are there".
 *
 * The other, `scripts/rice-update.py`, answers a different question — which
 * commits this config is behind — and backs the shell's own Updates surface,
 * which drives a rice-updater contract (`behind`, `fromDate`, `changelog`,
 * `conflicts`, `missingDeps`, `version`, and a shell relaunch once the new code
 * lands). Pointing that surface at the package script reads a shape that never
 * arrives: no `behind` means "0 updates, all good", so it would say "Up to
 * date" with a pending upgrade in front of it. The two are kept apart for that
 * reason.
 *
 * Nothing here needs a shell reload — the packages are not the shell — so the
 * page reports, and offers only what the script does: check, apply, apply-minimal.
 */
Singleton {
    id: root

    readonly property string path: Paths.updater

    /** "", "ok" or "error" — the script's own status field. */
    property string status: ""
    property int pending: 0
    property var packages: []
    property string errorText: ""

    property bool checking: false
    property bool applying: false

    /** The last apply's outcome: the script's `applied` flag and its reboot hint. */
    property bool applied: false
    property bool rebootNeeded: false

    /** Per-command results of the last apply: `{ command, success, output }`. */
    property var results: []

    /** Strip version metadata from `dnf check-update`? That is `apply-minimal`. */
    property bool securityOnly: false

    /** Non-empty when the last run could not be read. */
    property string note: ""

    readonly property bool busy: checking || applying
    readonly property bool upToDate: status === "ok" && pending === 0
    readonly property bool behind: status === "ok" && pending > 0

    /** What the page's headline is about, in one word. */
    readonly property string statusKind: applying ? "applying"
        : checking ? "checking"
        : status === "error" ? "error"
        : behind ? "behind"
        : upToDate ? "ok"
        : "idle"

    /** Ask the script what is pending. Safe: `check` writes nothing. */
    function check() {
        if (root.busy)
            return;
        root.checking = true;
        root.applied = false;
        checkProc.running = true;
    }

    /**
     * Run the upgrade. The script escalates with pkexec itself, so a cancelled
     * password prompt comes back as a failed command rather than as an error here
     * — which is why the results are kept and shown.
     */
    function apply() {
        if (root.busy)
            return;
        root.applying = true;
        root.applied = false;
        root.results = [];
        applyProc.running = true;
    }

    /** The first package the last apply failed on, or "". */
    function failing() {
        for (var i = 0; i < root.results.length; i++)
            if (!root.results[i].success)
                return root.results[i];
        return null;
    }

    function ingestCheck(text) {
        var data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = null;
        }
        if (!data || data.status === undefined) {
            root.status = "error";
            root.errorText = "The updater returned something unexpected.";
            return;
        }
        root.status = data.status;
        root.pending = data.updates || 0;
        root.packages = data.packages || [];
        root.errorText = data.error || "";
    }

    function ingestApply(text) {
        var data = null;
        try {
            data = JSON.parse(text);
        } catch (e) {
            data = null;
        }
        if (!data || data.status === undefined) {
            root.status = "error";
            root.errorText = "The updater returned something unexpected.";
            return;
        }
        root.results = data.results || [];
        root.applied = data.applied === true;
        root.rebootNeeded = data.rebootNeeded === true;
        if (root.applied) {
            // A landed upgrade answers its own question, so the pending list is
            // cleared rather than left showing what was just installed.
            root.status = "ok";
            root.pending = 0;
            root.packages = [];
            root.errorText = "";
        } else {
            root.status = data.status === "ok" ? "ok" : "error";
            root.errorText = root.status === "error" ? "The upgrade did not finish." : "";
        }
    }

    Process {
        id: checkProc
        command: ["python3", root.path, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.checking = false;
                root.ingestCheck(this.text);
            }
        }
    }

    Process {
        id: applyProc
        command: ["python3", root.path, root.securityOnly ? "apply-minimal" : "apply"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.applying = false;
                root.ingestApply(this.text);
                // The pending list is stale either way: an apply that failed
                // part-way still installed something.
                checkProc.running = true;
            }
        }
    }
}
