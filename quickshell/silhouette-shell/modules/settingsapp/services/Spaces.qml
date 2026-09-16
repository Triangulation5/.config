pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.settingsapp.services
import "../utils/keybinds/spacebinds.js" as SpaceBinds

/**
 * The user's special workspaces, across the two files one actually needs.
 *
 * `spaces.lua` is the shell's own store: `{ id, name, desc, key, apps[] }` per
 * space, which the shell reads to name a space in its workspace readout and to
 * route the window classes listed in `apps` into it. That file is written
 * exactly as the shell's Spaces service writes it, so the two agree.
 *
 * But on this config *nothing requires spaces.lua* (`hyprland.lua` never lists
 * it) — a space would exist in the app and toggle nothing. The key is what the
 * compositor needs, and on this config the keys live in `modules/binds.lua`, so
 * creating or removing a space writes its `toggle_special` pair there too. That
 * is the one place this app deliberately goes beyond the shell's surface, and it
 * is why a space created here works without touching the config's load order.
 *
 * Both writes are atomic and both end in a reload. The space list is re-read
 * after a write rather than kept in memory: this is a file the user may also
 * edit by hand, and a stale list is a page that lies about what exists.
 */
Singleton {
    id: root

    readonly property string path: Paths.spaces
    readonly property string bindsPath: Paths.binds

    /** `spaces.lua` as last read, and the spaces parsed out of it. */
    property string text: ""
    property var list: []

    /** `binds.lua` as last read, and the specials its binds declare. */
    property string bindsText: ""

    /** Non-empty when the last write could not be made. */
    property string note: ""

    readonly property string header:
        "-- User-defined special workspaces. The Settings page rewrites this file, so keep\n"
        + "-- each entry on this shape. id is the special-workspace name, key is a single\n"
        + "-- Super-prefixed letter, apps are window classes that auto-route in.\n"

    /**
     * Every space the page shows: the ones this app manages (in `spaces.lua`,
     * `managed` true) followed by the ones the user declared by hand in the binds
     * (`managed` false — shown so the page accounts for them, but not edited,
     * because the file is theirs). A hand-written space whose id is also in
     * spaces.lua is the same space, and shows once, as managed.
     */
    function entries() {
        var out = [];
        for (var i = 0; i < root.list.length; i++) {
            var e = root.list[i];
            out.push({ id: e.id, name: e.name, desc: e.desc, key: lookup(e.id, e.key),
                       apps: e.apps || [], managed: true });
        }
        var bound = SpaceBinds.specials(root.bindsText);
        for (var j = 0; j < bound.length; j++) {
            if (byId(bound[j].id))
                continue;
            out.push({ id: bound[j].id, name: bound[j].id, desc: "", key: bound[j].combo,
                       apps: [], managed: false });
        }
        return out;
    }

    /** The spaces.lua entry with this id, or null. */
    function byId(id) {
        for (var i = 0; i < root.list.length; i++)
            if (root.list[i].id === id)
                return root.list[i];
        return null;
    }

    /**
     * The chord one space answers to, as shown on its row: the key the store
     * records as `SUPER + M`, or — for a space the store does not carry — the
     * combo its own bind declares.
     */
    function lookup(id, key) {
        if (key && key.length > 0)
            return "SUPER + " + key;
        var bound = SpaceBinds.specials(root.bindsText);
        for (var i = 0; i < bound.length; i++)
            if (bound[i].id === id)
                return "SUPER + " + bound[i].combo;
        return "";
    }

    /** Slug a display name into a lua-safe special-workspace id. */
    function slug(name) {
        return String(name).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    /** Strip what would unbalance the lua literal or this file's brace walk. */
    function clean(s) {
        return String(s).replace(/[{}\"\\\n\r]/g, "").trim();
    }

    /** The three ids every config already means something by. */
    function reserved(id) {
        return id === "stash" || id === "private" || id === "minimized";
    }

    /**
     * True when SUPER+`key` is taken: another space holds it, or binds.lua
     * already binds it — including the space's own SHIFT twin, so the two
     * halves of a pair can never be split by a second space claiming one of them.
     */
    function keyTaken(key) {
        if (!key || key.length === 0)
            return false;
        var mod = SpaceBinds.modValue(root.bindsText);
        return SpaceBinds.inUse(root.bindsText, mod + " + " + key.toUpperCase())
            || SpaceBinds.inUse(root.bindsText, mod + " + SHIFT + " + key.toUpperCase());
    }

    /**
     * Why `name`/`key` cannot become a space, or "" when they can. The page shows
     * this as it is typed rather than writing and reverting: a create that
     * silently does nothing is the worst of both.
     */
    function problem(name, key) {
        var trimmed = String(name).trim();
        if (trimmed.length === 0)
            return "name empty";
        var id = slug(trimmed);
        if (id.length === 0)
            return "name needs a letter";
        if (reserved(id))
            return trimmed + " is reserved";
        if (byId(id))
            return trimmed + " already exists";
        // A space the user bound by hand is not in the store, but its id is
        // taken: adding it here would write a second toggle for the same name.
        if (SpaceBinds.has(root.bindsText, id))
            return trimmed + " is already bound";
        if (key.length === 0)
            return "pick a key";
        if (keyTaken(key))
            return "Super + " + key.toUpperCase() + " is in use";
        return "";
    }

    /** Create a space: the store entry, then the binds that make it toggle. */
    function addSpace(name, desc, key) {
        if (problem(name, key).length > 0)
            return false;
        var id = slug(name);
        var next = root.list.slice();
        next.push({ id: id, name: clean(name), desc: clean(desc), key: clean(key.toUpperCase()), apps: [] });
        spaceWriter.setText(fileText(next));
        var binds = SpaceBinds.add(root.bindsText, id, key.toUpperCase());
        if (!binds.ok) {
            root.note = "Could not add the bind for " + id + ": " + binds.error + ".";
            return false;
        }
        root.note = "";
        root.bindsText = binds.text;
        bindsWriter.setText(binds.text);
        return true;
    }

    /** Remove a space and the binds that toggle it. */
    function removeSpace(id) {
        var next = root.list.filter(function (e) { return e.id !== id; });
        if (next.length !== root.list.length)
            spaceWriter.setText(fileText(next));
        var binds = SpaceBinds.remove(root.bindsText, id);
        if (!binds.ok) {
            root.note = "Removed " + id + ", but it has no bind in " + root.bindsPath + ".";
            return;
        }
        root.note = "";
        root.bindsText = binds.text;
        bindsWriter.setText(binds.text);
    }

    /** Route one window class into a space, as the shell's app manager does. */
    function addApp(id, cls) {
        cls = clean(cls);
        if (cls.length === 0)
            return;
        var next = root.list.slice();
        for (var i = 0; i < next.length; i++) {
            if (next[i].id !== id)
                continue;
            var apps = (next[i].apps || []).slice();
            if (apps.indexOf(cls) >= 0)
                return;
            apps.push(cls);
            next[i] = entryWith(next[i], apps);
            spaceWriter.setText(fileText(next));
            return;
        }
    }

    /** Stop routing one window class into a space. */
    function removeApp(id, cls) {
        var next = root.list.slice();
        for (var i = 0; i < next.length; i++) {
            if (next[i].id !== id)
                continue;
            next[i] = entryWith(next[i], (next[i].apps || []).filter(function (a) { return a !== cls; }));
            spaceWriter.setText(fileText(next));
            return;
        }
    }

    /** `entry` with its app list replaced. */
    function entryWith(entry, apps) {
        return { id: entry.id, name: entry.name, desc: entry.desc, key: entry.key, apps: apps };
    }

    /** Pull the fields out of one `{ ... }` entry block, or null without an id. */
    function parseEntry(block) {
        var id = field(block, "id");
        if (id.length === 0)
            return null;
        var apps = [];
        var list = /apps\s*=\s*{([^}]*)}/.exec(block);
        if (list) {
            var re = /"([^"]*)"/g;
            var m;
            while ((m = re.exec(list[1])) !== null)
                if (m[1].length > 0)
                    apps.push(m[1]);
        }
        return { id: id, name: field(block, "name") || id, desc: field(block, "desc"),
                 key: field(block, "key"), apps: apps };
    }

    /** One string field of an entry block; "" when it is absent. */
    function field(block, key) {
        var m = new RegExp("\\b" + key + "\\s*=\\s*\"([^\"]*)\"").exec(block);
        return m ? m[1] : "";
    }

    /**
     * Walk the `return { ... }` table brace by brace and parse each top-level
     * entry: the nested `apps = { ... }` sits one level deeper, so it never opens
     * an entry of its own.
     */
    function parse(text) {
        var ri = text.indexOf("return");
        var body = ri >= 0 ? text.slice(ri) : text;
        var open = body.indexOf("{");
        if (open < 0)
            return [];
        var out = [];
        var depth = 0;
        var start = -1;
        for (var i = open; i < body.length; i++) {
            var c = body[i];
            if (c === "{") {
                depth++;
                if (depth === 2)
                    start = i;
            } else if (c === "}") {
                if (depth === 2 && start >= 0) {
                    var entry = parseEntry(body.slice(start, i + 1));
                    if (entry)
                        out.push(entry);
                    start = -1;
                }
                depth--;
                if (depth === 0)
                    break;
            }
        }
        return out;
    }

    /** The whole file for `arr`, in the shape the shell's store writes. */
    function fileText(arr) {
        var body = "return {\n";
        for (var i = 0; i < arr.length; i++) {
            var e = arr[i];
            var apps = "";
            var src = e.apps || [];
            for (var j = 0; j < src.length; j++)
                apps += (j ? ", " : "") + "\"" + src[j] + "\"";
            body += "\t{ id = \"" + e.id + "\", name = \"" + e.name + "\", desc = \"" + (e.desc || "")
                + "\", key = \"" + (e.key || "") + "\", apps = " + (src.length ? "{ " + apps + " }" : "{}") + " },\n";
        }
        return root.header + body + "}\n";
    }

    FileView {
        id: spaceFile
        path: root.path
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.text = spaceFile.text();
            root.list = root.parse(root.text);
        }
        onFileChanged: reload()
    }

    FileView {
        id: bindsFile
        path: root.bindsPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.bindsText = bindsFile.text()
        onFileChanged: reload()
    }

    FileView {
        id: spaceWriter
        path: root.path
        atomicWrites: true
        printErrors: false
        onSaved: {
            spaceFile.reload();
            Hypr.reload();
        }
        onSaveFailed: function (error) { root.note = "Could not write " + root.path + ": " + error + "."; }
    }

    FileView {
        id: bindsWriter
        path: root.bindsPath
        atomicWrites: true
        printErrors: false
        onSaved: {
            bindsFile.reload();
            Hypr.reload();
        }
        onSaveFailed: function (error) { root.note = "Could not write " + root.bindsPath + ": " + error + "."; }
    }
}
