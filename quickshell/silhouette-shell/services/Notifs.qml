pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Notification service. Wraps the NotificationServer into the grouped live and
 * history lists the tray and inbox render, tracks arrival times, unread counts,
 * and popups, and offers dismiss/activate helpers that raise the notifying app's
 * window.
 */

Singleton {
    id: root

    property var seenIds: ({})
    property var arrivalMs: ({})
    property var popups: []
    property int tick: 0
    property var expandedApps: ({})
    property var history: []
    property var userDismissed: ({})
    property var expireAt: ({})
    property var hookedIds: ({})

    readonly property var tracked: server.trackedNotifications.values
    readonly property int count: tracked.length + history.length

    readonly property int unread: {
        var u = 0;
        for (var i = 0; i < tracked.length; i++)
            if (!seenIds[tracked[i].id]) u++;
        return u;
    }

    /**
     * The grouped tree the tray renders.
     *
     * Built by rebuildGroups() and *scheduled* once per change rather than
     * evaluated as a binding: a single notification close reassigns arrivalMs,
     * history, expireAt and hookedIds in a row, and a binding would redo the
     * whole sort-and-coalesce pass once per assignment instead of once per
     * change. The schedule collapses to the next event-loop turn, so the tree
     * still lands in the frame it used to.
     *
     * `liveSig` below is what re-schedules it: a cheap signature over the live
     * list's ids and the fields coalesce() reads, so the rebuild still fires if
     * a live notification's summary or urgency changes in place — which is what
     * a plain binding used to catch for free.
     */
    property var groups: []
    property bool groupsPending: false

    readonly property string liveSig: {
        var s = "";
        for (var i = 0; i < tracked.length; i++)
            s += tracked[i].id + ":" + tracked[i].summary + ":" + tracked[i].urgency + ";";
        return s;
    }

    onLiveSigChanged: root.scheduleGroups()
    onHistoryChanged: root.scheduleGroups()
    /** Arrival times order the groups, and the shell restores tracked notifications
      * on reload without the list itself changing — so this one is not redundant
      * with liveSig. */
    onArrivalMsChanged: root.scheduleGroups()

    function scheduleGroups() {
        if (root.groupsPending)
            return;
        root.groupsPending = true;
        Qt.callLater(root.rebuildGroups);
    }

    function rebuildGroups() {
        root.groupsPending = false;
        var map = {};
        var order = [];
        for (var i = 0; i < tracked.length; i++) {
            var n = tracked[i];
            var app = (n.appName && n.appName.length) ? n.appName : "System";
            if (map[app] === undefined) { map[app] = []; order.push(app); }
            map[app].push({ live: true, n: n, t: arrivalMs[n.id] || 0 });
        }
        for (var j = 0; j < history.length; j++) {
            var h = history[j];
            if (map[h.app] === undefined) { map[h.app] = []; order.push(h.app); }
            map[h.app].push({ live: false, n: h, t: h.ts || 0 });
        }
        function coalesce(list, it) {
            var last = list.length > 0 ? list[list.length - 1] : null;
            if (last && last.n.summary === it.n.summary && last.n.body === it.n.body) {
                last.count++;
                last.items.push(it.n);
            } else {
                list.push({ live: it.live, n: it.n, count: 1, items: [it.n] });
            }
        }
        var gs = order.map(function(app) {
            var items = map[app];
            items.sort(function(a, b) { return b.t - a.t; });
            var criticals = [];
            var entries = [];
            for (var k = 0; k < items.length; k++)
                coalesce(items[k].n.urgency === NotificationUrgency.Critical ? criticals : entries, items[k]);
            var preview = items.find(function(it) { return it.n.urgency !== NotificationUrgency.Critical; });
            return {
                app: app,
                count: items.length,
                t: items[0].t,
                newest: items[0].n,
                preview: preview ? preview.n : items[0].n,
                criticals: criticals,
                entries: entries
            };
        });
        gs.sort(function(a, b) { return b.t - a.t; });
        root.groups = gs;
    }

    function iconFor(n) {
        if (!n) return "";
        var img = n.image || "";
        var names = [];
        if (img.indexOf("image://icon/") === 0) {
            names.push(img.substring(13));
        } else if (img.length && !/\.svg$/i.test(img)) {
            return img;
        }
        names.push(n.appIcon, n.desktopEntry, (n.appName || n.app || "").toLowerCase());
        for (var i = 0; i < names.length; i++) {
            var nm = names[i];
            if (!nm || !nm.length) continue;
            if (nm.indexOf("/") === 0 || nm.indexOf("file://") === 0) return nm;
            var p = Quickshell.iconPath(nm, true);
            if (p.length) return p;
        }
        return "";
    }

    function dismissEntry(e) {
        if (!e || !e.items) return;
        var d = Object.assign({}, userDismissed);
        var gone = {};
        var live = [];
        for (var i = 0; i < e.items.length; i++) {
            var n = e.items[i];
            if (typeof n.dismiss === "function") {
                d[n.id] = true;
                live.push(n);
            } else {
                gone[n.id] = true;
            }
        }
        root.userDismissed = d;
        for (var j = 0; j < live.length; j++) live[j].dismiss();
        root.history = root.history.filter(function(h) { return !gone[h.id]; });
    }

    /**
     * Focus the app's Hyprland window (workspace switch included) by matching the
     * notification's desktopEntry/appName against the live window classes.
     */
    function raiseWindow(n) {
        if (!n) return;
        var token = String(n.desktopEntry && n.desktopEntry.length ? n.desktopEntry : (n.appName || "")).toLowerCase();
        if (token.length === 0) return;
        Quickshell.execDetached(["sh", "-c",
            "addr=$(hyprctl clients -j | jq -r --arg q \"$1\" 'first(.[] | select(((.class | if . then ascii_downcase else \"\" end) | contains($q)) or ((.initialClass | if . then ascii_downcase else \"\" end) | contains($q))) | .address)'); [ -n \"$addr\" ] && hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\"",
            "sh", token]);
    }

    /**
     * Open the app behind a notification: invoke its default action when present,
     * then jump to the app's window, mirroring stock notification-center behavior.
     */
    function activateNotif(n) {
        if (!n) return;
        var acts = n.actions || [];
        for (var i = 0; i < acts.length; i++) {
            if (acts[i].identifier === "default") {
                acts[i].invoke();
                break;
            }
        }
        raiseWindow(n);
    }

    /** Inbox-row entry wrapper: activate the app, then dismiss the entry. */
    function activateEntry(e) {
        if (!e || !e.n) return;
        activateNotif(e.n);
        dismissEntry(e);
    }

    function dismissApp(app) {
        var doomed = tracked.filter(function(n) {
            return ((n.appName && n.appName.length) ? n.appName : "System") === app;
        });
        var d = Object.assign({}, userDismissed);
        for (var i = 0; i < doomed.length; i++) d[doomed[i].id] = true;
        root.userDismissed = d;
        for (var j = 0; j < doomed.length; j++) doomed[j].dismiss();
        root.history = root.history.filter(function(h) { return h.app !== app; });
    }

    function markAllSeen() {
        var m = {};
        for (var i = 0; i < tracked.length; i++) m[tracked[i].id] = true;
        root.seenIds = m;
    }

    function clearAll() {
        var l = tracked.slice();
        var d = Object.assign({}, userDismissed);
        for (var i = 0; i < l.length; i++) d[l[i].id] = true;
        root.userDismissed = d;
        for (var j = 0; j < l.length; j++) l[j].dismiss();
        root.history = [];
        root.popups = [];
    }

    function removePopup(n) {
        root.popups = root.popups.filter(function(p) { return p !== n; });
    }

    /**
     * Return the first action whose identifier suggests an inline reply
     * (contains "reply" case-insensitively), or null when none.
     */
    function replyAction(n) {
        if (!n) return null;
        var acts = n.actions || [];
        for (var i = 0; i < acts.length; i++) {
            var id = String(acts[i].identifier || "").toLowerCase();
            if (id.indexOf("reply") !== -1 || id.indexOf("inline-reply") !== -1)
                return acts[i];
        }
        return null;
    }

    function toggleExpanded(app) {
        var e = Object.assign({}, expandedApps);
        e[app] = e[app] !== true;
        root.expandedApps = e;
    }

    /**
     * Bind the history-snapshot handler to a notification's `closed` signal once.
     * `keepOnReload` re-runs Component.onCompleted on every QS reload over the
     * still-tracked notifications, so the id set gates re-hooks: without it each
     * reload would stack another handler and a single close would push duplicate
     * history rows. The id is cleared inside the handler so a later notification
     * reusing the id re-hooks cleanly.
     */
    function hookClosed(n) {
        if (root.hookedIds[n.id])
            return;
        var hooked = Object.assign({}, root.hookedIds);
        hooked[n.id] = true;
        root.hookedIds = hooked;
        n.closed.connect(function(reason) {
            if (!root.userDismissed[n.id])
                root.history = [{
                    app: (n.appName && n.appName.length) ? n.appName : "System",
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    desktopEntry: n.desktopEntry,
                    image: n.image,
                    urgency: n.urgency,
                    ts: root.arrivalMs[n.id] || Date.now(),
                    id: "h" + n.id + "-" + Date.now()
                }].concat(root.history).slice(0, Math.max(1, Flags.notifHistoryMax));
            else {
                var du = Object.assign({}, root.userDismissed);
                delete du[n.id];
                root.userDismissed = du;
            }
            root.removePopup(n);
            var b = Object.assign({}, root.arrivalMs);
            delete b[n.id];
            root.arrivalMs = b;
            var c = Object.assign({}, root.expireAt);
            delete c[n.id];
            root.expireAt = c;
            var h = Object.assign({}, root.hookedIds);
            delete h[n.id];
            root.hookedIds = h;
        });
    }

    function ageLabel(n) {
        void root.tick;
        var t = arrivalMs[n.id] || n.ts;
        if (!t) return "";
        var m = Math.floor((Date.now() - t) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m";
        return Math.floor(m / 60) + "h";
    }

    Timer {
        interval: 30000
        running: root.count > 0
        repeat: true
        onTriggered: root.tick++
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        Component.onCompleted: {
            var l = trackedNotifications.values;
            var a = Object.assign({}, root.arrivalMs);
            for (var i = 0; i < l.length; i++) {
                if (!a[l[i].id]) a[l[i].id] = Date.now();
                root.hookClosed(l[i]);
            }
            root.arrivalMs = a;
        }

        onNotification: function(n) {
            var a = Object.assign({}, root.arrivalMs);
            a[n.id] = Date.now();
            root.arrivalMs = a;
            var e = Object.assign({}, root.expireAt);
            e[n.id] = Date.now() + Math.max(1000, n.urgency === NotificationUrgency.Low
                ? Flags.notifLowMs : Flags.notifMs);
            root.expireAt = e;
            n.tracked = true;
            root.hookClosed(n);
            var critical = n.urgency === NotificationUrgency.Critical;
            if (!GameMode.dnd || (critical && Flags.dndCritical)) {
                /**
                 * A repeat of something already on screen is not a second
                 * toast. The repeat is still tracked and still folds into the
                 * tray's group count, so nothing is lost by leaving the stack
                 * alone — the popup just stops stacking identical rows.
                 */
                if (isDuplicatePopup(n))
                    return;
                root.popups = root.popups.concat([n]).slice(-Math.max(1, Flags.notifPopupMax));
                if (Flags.notifSound)
                    chime.running = true;
            }
        }
    }

    /**
     * True when an identical notification — same app, summary and body — is
     * already in the popup stack. Gated by the `notifDedupe` flag so the old
     * always-stack behaviour is one toggle away.
     */
    function isDuplicatePopup(n) {
        if (!Flags.notifDedupe)
            return false;
        var app = (n.appName && n.appName.length) ? n.appName : "System";
        for (var i = 0; i < root.popups.length; i++) {
            var p = root.popups[i];
            if (!p)
                continue;
            var papp = (p.appName && p.appName.length) ? p.appName : "System";
            if (papp === app && p.summary === n.summary && p.body === n.body)
                return true;
        }
        return false;
    }

    /**
     * Optional notification sound, off by default: the freedesktop message
     * blip through the same `paplay` route the calendar reminder and the timer
     * already use, played once per notification that is actually shown.
     */
    Process {
        id: chime
        command: ["paplay", "/usr/share/sounds/freedesktop/stereo/message.oga"]
    }
}
