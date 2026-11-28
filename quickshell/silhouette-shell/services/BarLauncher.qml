pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import "../utils/launcher/fuzzy.js" as Fuzzy

/**
 * State and actions of the minimal bar's in-strip launcher (modules/bar/Dmenu.qml).
 *
 * The launcher is a mode of the bar, not a window of its own: while `open`, the
 * strip on `monitor` stops drawing its readouts and draws a prompt, an input and
 * a horizontal run of matches in their place, the way dmenu takes over a dwm bar.
 *
 * Desktop entry filtering, usage persistence, and crash-guarded/terminal-aware
 * launching live in `services/AppLauncher.qml` so every launcher shares one
 * implementation.
 */
Singleton {
    id: root

    property bool open: false

    /** The output whose strip carries the launcher. */
    property string monitor: ""
    property string query: ""
    property int selected: 0

    readonly property var allEntries: root.open ? AppLauncher.allEntries : []
    readonly property int total: root.open ? AppLauncher.total : 0
    readonly property var results: {
        if (!root.open)
            return [];
        void LauncherMatch.lastSeq;
        var rust = LauncherMatch.resolve(allEntries);
        return rust !== null ? rust : Fuzzy.rank(allEntries, query, AppLauncher.usage);
    }

    Connections {
        target: AppLauncher
        function onAllEntriesChanged() {
            if (root.open)
                LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
        }
        function onUsageChanged() {
            if (root.open)
                LauncherMatch.sync(AppLauncher.allEntries, root.query, AppLauncher.usage);
        }
    }

    onQueryChanged: if (root.open) LauncherMatch.sendQuery(query)

    /**
     * The output to open on. Checks the requested name against connected
     * screens, falling back to the focused output, then the first screen.
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

    function launchApp(entry) {
        AppLauncher.launch(entry);
    }

    /** Launch the selected match and close; counts the launch so it ranks higher next time. */
    function accept() {
        var entry = root.current();
        if (!entry)
            return;
        AppLauncher.launchAndRecord(entry);
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
        LauncherMatch.setConsumer("bar", root.open);
        if (root.open) {
            AppLauncher.reloadUsage();
            LauncherMatch.sync(AppLauncher.allEntries, query, AppLauncher.usage);
        }
    }
}
