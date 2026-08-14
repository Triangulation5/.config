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

    readonly property string base: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ricelin-polkit"
    readonly property string respFile: base + "/response"
    readonly property string agentScript: Qt.resolvedUrl("../utils/polkit/agent.py").toString().replace(/^file:\/\//, "")

    /** True while a prompt is live and the pill should show the auth face. */
    property bool pending: false
    property string message: ""
    property string action: ""
    property string user: ""

    /**
     * Send the typed password back to the agent. The password rides through a
     * short-lived argv into the response file; the file sits in the user-only
     * runtime dir and is deleted by the agent as soon as it is read.
     */
    function respond(password) {
        if (!pending)
            return;
        /** Reset first so a second answer (e.g. Cancel after a failed attempt) always re-runs the write. */
        writeProc.running = false;
        writeProc.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", password, root.respFile];
        writeProc.running = true;
    }

    /** Dismiss the prompt: the agent reads CANCEL and clears the conversation. */
    function cancel() {
        respond("CANCEL");
    }

    /** The agent daemon, autostarted with the shell and revived if it dies. */
    Process {
        id: agentProc
        command: ["python3", root.agentScript]
        running: true
        onExited: restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: agentProc.running = true
    }

    Process { id: writeProc }
}
