pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Bridge to the polkit authentication agent (utils/polkit/agent.py). The agent
 * registers with polkitd on the system bus and pokes the shell with
 * `qs ipc call polkit prompt` whenever an app needs admin rights; PillRoot's
 * ipc handler parks the state here and morphs the pill into the authorize
 * face. `respond()` / `cancel()` write the password (or CANCEL) to a file the
 * agent relays to the setuid polkit-agent-helper-1, which runs the polkit-1
 * PAM stack as root — so password and biometric modules in
 * /etc/pam.d/polkit-1 both unlock prompts through this same face.
 */
Singleton {
    id: root

    readonly property string base: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/silhouette-polkit"
    readonly property string respFile: base + "/response"
    readonly property string agentScript: Qt.resolvedUrl("../utils/polkit/agent.py").toString().replace(/^file:\/\//, "")
    readonly property string configDir: Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
    readonly property string rustBin: Quickshell.env("HOME") + "/.config/scripts/bin/silhouette-tools"

    /**
     * Latched true if `silhouette-tools polkit-agent` fails immediately on
     * startup (e.g. binary not built yet), so we seamlessly fall back to
     * `utils/polkit/agent.py`. Cleared when `Flags.useRustTools` is toggled on.
     */
    property bool rustUnavailable: false
    property real agentStartedAt: 0
    readonly property bool useRust: Flags.useRustTools && !root.rustUnavailable

    onUseRustChanged: {
        restartTimer.stop();
        agentProc.running = false;
        Qt.callLater(function() { agentProc.running = true; });
    }

    Connections {
        target: Flags
        function onUseRustToolsChanged() {
            if (Flags.useRustTools)
                root.rustUnavailable = false;
        }
    }

    /** True while a prompt is live and the pill should show the auth face. */
    property bool pending: false
    property string message: ""
    property string action: ""
    property string user: ""

    /**
     * Send the typed password back to the agent. The password is written directly
     * in-process to the response file without passing through command-line argv;
     * the file sits in the user-only runtime dir and is deleted by the agent as
     * soon as it is read.
     */
    function respond(password) {
        if (!pending)
            return;
        respWriter.setText(String(password || ""));
    }

    /** Dismiss the prompt: the agent reads CANCEL and clears the conversation. */
    function cancel() {
        respond("CANCEL");
    }

    FileView {
        id: respWriter
        path: root.respFile
        atomicWrites: true
        printErrors: false
    }

    /**
     * The agent daemon, autostarted with the shell and revived if it dies. A
     * stale agent from a previous shell can linger and keep polkitd's session
     * registration; in that case the agent itself exits 0 (see agent.py), and
     * this handler only revives on a real crash (non-zero exit) — so the old
     * duplicate-registration crash loop can never happen again.
     */
    Process {
        id: agentProc
        command: root.useRust
            ? [root.rustBin, "polkit-agent", "--config", root.configDir]
            : ["python3", root.agentScript]
        running: true
        onRunningChanged: {
            if (running)
                root.agentStartedAt = Date.now();
        }
        onExited: function(exitCode) {
            /** Exit 0 = "another agent already owns the session" — don't fight it. */
            if (exitCode === 0)
                return;
            if (root.useRust && (Date.now() - root.agentStartedAt) < 1000) {
                root.rustUnavailable = true;
                return;
            }
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: agentProc.running = true
    }
}
