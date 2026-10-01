pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../utils/launcher/fuzzy.js" as Fuzzy

/**
 * State and actions of the minimal bar's in-strip launcher (modules/bar/Dmenu.qml).
 *
 * The launcher is a mode of the bar, not a window of its own: while `open`, the
 * strip on `monitor` stops drawing its readouts and draws a prompt, an input and
 * a horizontal run of matches in their place, the way dmenu takes over a dwm bar.
 * This singleton is the one place that says whether it is open, on which output,
 * what has been typed and which match is selected — the strip on every other
 * output only reads `open` and `monitor` to know it is not the one.
 *
 * It reuses the standalone launcher's own machinery rather than growing a second
 * set of rules: the same fuzzy ranking (utils/launcher/fuzzy.js), the same usage
 * file, so the apps you open most rise to the top in both, and the same
 * launch-guard script, so an app that dies on startup fails loudly the same way.
 * The file is watched, so a launch from the other launcher is picked up here too.
 *
 * It answers to the standalone launcher's own IPC target and keybind as well:
 * while the bar is the shell, `launcher show|hide|toggle` (see LauncherRoot) is
 * routed here instead of raising the full-screen overlay, so one bind opens
 * whichever launcher belongs to the presentation on screen.
 *
 * The ranked list is built only while the launcher is open: the bar is on screen
 * all day and the launcher a few seconds of it.
 */
Singleton {
    id: root

    property bool open: false

    /** The output whose strip carries the launcher. */
    property string monitor: ""
    property string query: ""
    property int selected: 0
    property var usage: ({})

    readonly property var allEntries: {
        if (!root.open)
            return [];
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && !src[i].noDisplay)
                out.push(src[i]);
        return out;
    }

    readonly property int total: allEntries.length
    readonly property var results: root.open ? Fuzzy.rank(allEntries, query, usage) : []

    readonly property string guardScript: Quickshell.env("HOME") + "/.config/hypr/scripts/launch-guard.sh"

    FileView {
        id: usageStore
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/silhouette/launcher-usage.json"
        atomicWrites: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseUsage(usageStore.text())
        onLoadFailed: root.parseUsage("")
    }

    function parseUsage(raw) {
        try {
            root.usage = raw && raw.length ? JSON.parse(raw) : ({});
        } catch (e) {
            root.usage = ({});
        }
    }

    /**
     * The output to open on. The standalone launcher's bind hands over a monitor
     * name of its own making (or none), so whatever arrives is checked against
     * the screens that exist: a real name is honoured, anything else falls back
     * to the focused output, then to the first, so the launcher can never open on
     * an output with no strip to carry it.
     */
    function resolve(mon) {
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++)
            if (screens[i].name === mon)
                return mon;
        if (Hyprland.focusedMonitor)
            return Hyprland.focusedMonitor.name;
        return screens.length > 0 ? screens[0].name : "";
    }

    function show(mon) {
        root.query = "";
        root.selected = 0;
        root.monitor = root.resolve(mon);
        root.open = true;
    }

    function hide() {
        root.open = false;
        root.query = "";
        root.selected = 0;
    }

    function toggle(mon) {
        if (root.open)
            root.hide();
        else
            root.show(mon);
    }

    /** Step the selection by `delta` matches, stopping at the ends as dmenu does. */
    function move(delta) {
        var n = root.results.length;
        if (n === 0)
            return;
        root.selected = Math.max(0, Math.min(n - 1, root.selected + delta));
    }

    function current() {
        return root.results.length > 0 ? root.results[root.selected] : null;
    }

    /**
     * entry.execute() is fire and forget, so an app that dies on startup fails
     * silently; the guard script watches the first seconds and toasts the exit
     * code plus stderr when it does. Same call the standalone launcher makes.
     */
    function launchApp(entry) {
        if (!entry.command || entry.command.length === 0) {
            entry.execute();
            return;
        }
        Quickshell.execDetached(["bash", root.guardScript, entry.name, entry.icon || "", entry.workingDirectory || ""].concat(entry.command));
    }

    /** Launch the selected match and close; counts the launch so it ranks higher next time. */
    function accept() {
        var entry = root.current();
        if (!entry)
            return;
        if (entry.id) {
            root.usage[entry.id] = (root.usage[entry.id] || 0) + 1;
            /** Fire-and-forget: the write is async, so a launch never waits on disk. */
            usageStore.setText(JSON.stringify(root.usage));
        }
        root.launchApp(entry);
        root.hide();
    }

    /** dmenu's escape hatch: run what was typed, as typed, as a shell command. */
    function runTyped() {
        var text = root.query.trim();
        if (text.length === 0)
            return;
        Quickshell.execDetached(["sh", "-c", text]);
        root.hide();
    }

    /** Take the latest usage counts each time it opens. */
    onOpenChanged: {
        if (root.open)
            usageStore.reload();
    }
}
