pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Networking
import qs.services

/**
 * WLAN automation for the wifi drill-in: the rescan, security and profile
 * polls, the password-fed connect process with failed-profile cleanup, and the
 * on-demand PSK reveal. All surface state lives on the host (`host`); this
 * object only drives the nmcli work and writes results back into host
 * properties. `refreshSoon` debounces a list refresh after the network scan
 * changes.
 */
Item {
    id: root

    property var host: null

    function refreshSoon() {
        if (host.active)
            secRefresh.restart();
    }

    Binding {
        target: host.wifiDev
        property: "scannerEnabled"
        value: host.active && host.wifiOn
        when: host.wifiDev !== null
    }

    Timer {
        id: scanTimer
        interval: 10000
        onTriggered: host.stopScan()
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
    }

    Process {
        id: secProc
        command: ["nmcli", "-t", "-f", "SSID,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].length)
                        continue;
                    var parts = root.host.splitTerse(lines[i]);
                    if (parts && parts.head.length)
                        map[parts.head] = parts.tail;
                }
                root.host.securityMap = map;
            }
        }
    }

    Process {
        id: profProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var set = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = root.host.splitTerse(lines[i]);
                    if (parts && parts.head.length && parts.tail === "802-11-wireless")
                        set[parts.head] = true;
                }
                root.host.knownProfiles = set;
            }
        }
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: {
            write(root.host.pendingPw + "\n");
            root.host.pendingPw = "";
        }
        onExited: function(exitCode) {
            root.host.connecting = false;
            if (exitCode === 0) {
                root.host.expandedSsid = "";
                root.host.pwDraft = "";
                root.host.connectFailed = false;
                root.host.refresh();
            } else {
                root.host.connectFailed = true;
                if (!root.host.attemptWasKnown && root.host.attemptSsid.length) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", root.host.attemptSsid];
                    cleanupProc.running = true;
                }
            }
        }
    }

    /**
     * A failed `nmcli dev wifi connect` still leaves a connection profile
     * named after the SSID behind; without deleting it the network would be
     * treated as known on the next click and silently fail forever.
     */
    Process {
        id: cleanupProc
        onExited: root.host.refresh()
    }

    /**
     * Drops a saved profile on Forget. The list refreshes on exit so the row
     * loses its known/connected state and its lock falls back to dim.
     */
    Process {
        id: forgetProc
        onExited: root.host.refresh()
    }

    /**
     * Reads one saved profile's PSK on demand. The result is held only as long as
     * the row stays open; an empty result means the profile is open or stores no
     * recoverable secret, surfaced by the row as a plain note.
     */
    Process {
        id: revealProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.host.revealedPw = this.text.replace(/\n+$/, "");
                root.host.revealResolved = true;
            }
        }
    }

    Timer {
        id: secRefresh
        interval: 1200
        onTriggered: if (root.host.active) secProc.running = true
    }
}
