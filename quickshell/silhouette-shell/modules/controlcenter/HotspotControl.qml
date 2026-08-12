pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * State and control for the shared hotspot in the wifi drill-in: the live
 * name/password, active/busy flags, the inline-edit draft, and the nmcli
 * processes that bring the AP up/down and re-read its state. The view
 * (WifiHotspot) renders this state and emits toggle/edit signals back in.
 *
 * The `Singleton` root is used only as a non-visual object container (same as
 * ScreenRec) — there is no `pragma Singleton`, so each wifi surface gets its
 * own independent control.
 */
Singleton {
    id: ctl

    /** Wifi interface the AP binds to, fed live by the surface's wifi device. */
    property string iface: "wlan0"
    readonly property string con: "silhouette-shell"

    property string name: "SilhouetteShell"
    property string pw: ""
    property bool active: false
    property bool busy: false
    property string edit: ""
    property string draft: ""

    /**
     * Flips the shared hotspot: stop when active, else generate a password
     * (when none is set) and bring the AP up. Shared by the toggle and the
     * keyboard cursor.
     */
    function toggle() {
        if (busy)
            return;
        if (active) {
            stop();
        } else {
            if (pw.length < 8)
                pw = generatePw();
            apply();
        }
    }

    /** Re-reads the AP's active state and stored name/password from nmcli. */
    function refresh() {
        stateProc.running = true;
        readProc.running = true;
    }

    /**
     * Brings the shared AP up with the current name and password, creating the
     * persistent connection on first use and modifying it on later changes.
     * Name and password are passed as positional arguments, never spliced into
     * the shell string, so an odd character cannot break or inject the command.
     */
    function apply() {
        if (busy || pw.length < 8)
            return;
        busy = true;
        applyProc.command = ["sh", "-c",
            'c="' + con + '"; '
            + 'if nmcli -t connection show "$c" >/dev/null 2>&1; then '
            +   'nmcli connection modify "$c" 802-11-wireless.ssid "$1" 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2"; '
            + 'else '
            +   'nmcli connection add type wifi ifname "$3" con-name "$c" autoconnect no 802-11-wireless.ssid "$1" 802-11-wireless.mode ap 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2" ipv4.method shared; '
            + 'fi; '
            + 'nmcli connection up "$c"',
            "sh", name, pw, iface];
        applyProc.running = true;
    }

    function stop() {
        if (busy)
            return;
        busy = true;
        downProc.running = true;
    }

    /**
     * Commits an inline name or password edit, ignoring a password shorter
     * than the 8-character WPA2 minimum. A live hotspot is re-applied so the
     * change takes effect at once.
     */
    function commitEdit() {
        if (edit === "name") {
            if (draft.length)
                name = draft;
        } else if (edit === "pw") {
            if (draft.length >= 8)
                pw = draft;
        }
        edit = "";
        if (active)
            apply();
    }

    /**
     * Builds an eight-character WPA2 password from an unambiguous alphabet,
     * used when the hotspot is switched on before a password has been set.
     */
    function generatePw() {
        var cs = "abcdefghijkmnpqrstuvwxyz23456789";
        var s = "";
        for (var i = 0; i < 8; i++)
            s += cs.charAt(Math.floor(Math.random() * cs.length));
        return s;
    }

    Process {
        id: applyProc
        onExited: {
            ctl.busy = false;
            ctl.refresh();
        }
    }

    Process {
        id: downProc
        command: ["nmcli", "connection", "down", ctl.con]
        onExited: {
            ctl.busy = false;
            ctl.refresh();
        }
    }

    Process {
        id: stateProc
        command: ["sh", "-c", "nmcli -t -f NAME connection show --active | grep -qx \"$1\" && echo on || echo off", "sh", ctl.con]
        stdout: StdioCollector {
            onStreamFinished: ctl.active = this.text.trim() === "on"
        }
    }

    Process {
        id: readProc
        command: ["nmcli", "-t", "-s", "-g", "802-11-wireless.ssid,802-11-wireless-security.psk", "connection", "show", ctl.con]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                if (lines.length >= 1 && lines[0].length)
                    ctl.name = lines[0];
                if (lines.length >= 2 && lines[1].length)
                    ctl.pw = lines[1];
            }
        }
    }
}
