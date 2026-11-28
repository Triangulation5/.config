pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Shared application catalog, usage frequency store, and crash-guarded launcher
 * for every launcher surface (pill launcher, standalone overlay, bar dmenu, and
 * app pickers).
 *
 * Centralizing this here guarantees:
 *   - `Terminal=true` desktop entries (`entry.runInTerminal`) route through
 *     Quickshell's terminal-aware `entry.execute()` instead of dying without a
 *     TTY under the crash guard.
 *   - One watched `launcher-usage.json` store keeps launch counts consistent
 *     across all launchers without duplicate `FileView`s.
 *   - When `Flags.useRustTools` is active and `silhouette-tools` is verified,
 *     non-terminal apps exec `silhouette-tools launch-guard` directly, skipping
 *     the `bash` wrapper and its subshell startup overhead.
 */
Singleton {
    id: root

    readonly property string guardScript: Quickshell.env("HOME") + "/.config/scripts/launch-guard.sh"
    readonly property string appimageScript: Quickshell.env("HOME") + "/.config/scripts/app-install.sh"
    readonly property string usageFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/silhouette/launcher-usage.json"

    property var usage: ({})

    readonly property var allEntries: {
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && !src[i].noDisplay)
                out.push(src[i]);
        return out;
    }

    readonly property int total: allEntries.length

    /** Cached lowercase desktop-id -> icon path map so window rows resolve in O(1). */
    readonly property var windowIconMap: {
        var apps = DesktopEntries.applications.values;
        var map = {};
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (!a || !a.id || !a.icon)
                continue;
            var id = a.id.toLowerCase();
            var icon = Quickshell.iconPath(a.icon, true);
            if (!icon)
                continue;
            map[id] = icon;
            if (id.endsWith(".desktop"))
                map[id.slice(0, -8)] = icon;
        }
        return map;
    }

    FileView {
        id: usageStore
        path: root.usageFile
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

    function reloadUsage() {
        usageStore.reload();
    }

    /** Record one launch for `entry`, updating disk async and notifying the Rust matcher in O(1). */
    function recordUsage(entry) {
        if (!entry || !entry.id)
            return;
        var next = Object.assign({}, root.usage);
        next[entry.id] = (next[entry.id] || 0) + 1;
        root.usage = next;
        LauncherMatch.bumpUsage(entry.id);
        usageStore.setText(JSON.stringify(next));
    }

    /**
     * Launch a DesktopEntry.
     *
     * Terminal apps (`entry.runInTerminal`) and entries without an explicit
     * `command` array delegate to `entry.execute()` so Quickshell allocates the
     * configured terminal emulator. Regular GUI apps run through `launch-guard`
     * so startup crashes raise a toast with stderr — invoking `silhouette-tools`
     * directly when Rust tools are verified, or falling back to `launch-guard.sh`.
     */
    function launch(entry) {
        if (!entry)
            return;
        if (entry.runInTerminal || !entry.command || entry.command.length === 0) {
            entry.execute();
            return;
        }
        var args = [entry.name || "", entry.icon || "", entry.workingDirectory || ""].concat(entry.command);
        if (Flags.useRustTools && LauncherMatch.rustVerified) {
            Quickshell.execDetached([Flags.rustBin, "launch-guard"].concat(args));
            return;
        }
        Quickshell.execDetached(["bash", root.guardScript].concat(args));
    }

    /** Record frequency and launch `entry` in one call. */
    function launchAndRecord(entry) {
        if (!entry)
            return;
        root.recordUsage(entry);
        root.launch(entry);
    }

    /**
     * The AppImage slug behind an entry id, or "" when it is not one of ours.
     * The drop-installer writes `silhouette-<slug>` now; `ricelin-<slug>` is what
     * entries installed before that rename look like, and they stay editable
     * instead of being orphaned by it.
     */
    function appimageSlug(entry) {
        if (!entry || !entry.id)
            return "";
        if (entry.id.indexOf("silhouette-") === 0)
            return entry.id.substring(11);
        if (entry.id.indexOf("ricelin-") === 0)
            return entry.id.substring(8);
        return "";
    }

    function isAppImage(entry) {
        return root.appimageSlug(entry).length > 0;
    }

    function iconForWindow(cls) {
        if (!cls || !cls.length)
            return "";
        var key = cls.toLowerCase();
        return root.windowIconMap[key] || root.windowIconMap[key + ".desktop"] || "";
    }

    function mapCategory(raw) {
        var order = [
            ["TerminalEmulator", "Terminal"], ["WebBrowser", "Browser"],
            ["InstantMessaging", "Chat"], ["Audio", "Media"], ["AudioVideo", "Media"],
            ["Video", "Media"], ["Game", "Game"], ["Development", "Dev"],
            ["Graphics", "Graphics"], ["Office", "Office"], ["Settings", "System"],
            ["System", "System"], ["Utility", "Tool"], ["Network", "Net"]
        ];
        var cats = String(raw).split(/[;,]/);
        for (var i = 0; i < order.length; i++)
            if (cats.indexOf(order[i][0]) !== -1)
                return order[i][1];
        return "";
    }
}
