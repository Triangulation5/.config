pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * State and actions of the minimal bar's in-strip power list
 * (modules/bar/PowerList.qml) — the bar's answer to the pill's power surface.
 *
 * The launcher already set the shape for this: a mode of the bar rather than a
 * window of its own, so while `open` the strip on `monitor` stops drawing its
 * readouts and draws a prompt, an input and a horizontal run of matches in their
 * place. Power needed the same thing, because the pill's Power surface is a
 * PillSurface and there is no pill to host one while the bar is the shell.
 *
 * It is searchable for the same reason the launcher is: a strip is a bad place to
 * hunt through a list with the eyes, and "shut" or "log" is faster than counting
 * to the fourth item. The filter is a plain case-insensitive substring on the
 * label rather than the launcher's fuzzy rank, because this list is five fixed
 * items that are all short, all distinct, and all spelled the way the user would
 * type them — fuzzy ranking has nothing to disambiguate here and would reorder
 * items that have a right order of their own.
 *
 * The action table is deliberately the same five in the same order as the pill's
 * (modules/controlcenter/Power.qml), including which ones are destructive, so the
 * two surfaces are the same menu in different clothes rather than two menus that
 * have to be kept in step by hand. The dispatch and argv are carried per action
 * and run here exactly as that surface runs them, so logout still goes through
 * `hl.dsp.exit()` and the rest still exec `systemctl` directly — no second set of
 * rules for the same verbs.
 *
 * Confirmation matches the pill's too, and for the same reason: a destructive
 * action cannot fire on one keypress. The bar has no heat fill to hold, so it
 * takes the double tap — the same two steps, expressed as two presses. See
 * `armOrAccept`.
 */
Singleton {
    id: root

    property bool open: false

    /** The output whose strip carries the list. */
    property string monitor: ""

    property string query: ""

    /** Index into `results`, not into `actions` — the two differ once filtered. */
    property int selected: 0

    /**
     * The destructive action armed by a first press, waiting for its second.
     * -1 is none. Expires on `armWindow`, so an item left armed by an earlier
     * press cannot fire from a much later one.
     */
    property int armedIndex: -1

    readonly property int armWindow: 2500

    readonly property string lockScript: Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"

    /**
     * The same five as the pill's power surface, same order, same `confirm` flags.
     * Mirrored rather than imported because that table is a `readonly var` built
     * inside a component that is not built while the bar is up — there is nothing
     * to read it from here.
     */
    readonly property var actions: [
        { key: "lock",     label: "Lock",     confirm: false, dispatch: "",                 argv: [root.lockScript] },
        { key: "logout",   label: "Logout",   confirm: true,  dispatch: "hl.dsp.exit()", argv: [] },
        { key: "suspend",  label: "Sleep",    confirm: false, dispatch: "",                 argv: ["systemctl", "suspend"] },
        { key: "reboot",   label: "Restart",  confirm: true,  dispatch: "",                 argv: ["systemctl", "reboot"] },
        { key: "shutdown", label: "Shutdown", confirm: true,  dispatch: "",                 argv: ["systemctl", "poweroff"] }
    ]

    /**
     * What the run actually draws: every action on an empty query, otherwise the
     * ones whose label contains it. A fresh array each time so the ListView-free
     * Repeater in PowerList sees a change — the same "replace, never mutate" rule
     * the rest of the shell keeps for `var` properties.
     */
    readonly property var results: {
        var q = root.query.trim().toLowerCase();
        if (q.length === 0)
            return root.actions.slice();
        var out = [];
        for (var i = 0; i < root.actions.length; i++)
            if (root.actions[i].label.toLowerCase().indexOf(q) >= 0)
                out.push(root.actions[i]);
        return out;
    }

    readonly property var current: (selected >= 0 && selected < results.length)
        ? results[selected] : null

    /** The action the label describes: the armed one first, else the selected. */
    readonly property var focused: (armedIndex >= 0 && armedIndex < results.length)
        ? results[armedIndex] : current

    readonly property bool armed: armedIndex >= 0 && armedIndex === selected

    /**
     * The output to open on, checked against the screens that exist so the list can
     * never open on an output with no strip to carry it. The same resolution the
     * launcher does (see BarLauncher.resolve), kept separate rather than shared:
     * the two are independent modes and neither is built while the bar is down, so
     * there is nothing to factor out that would not be a second owner of the rule.
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
        root.armedIndex = -1;
        armTimer.stop();
        root.monitor = root.resolve(mon);
        root.open = true;
    }

    function hide() {
        root.open = false;
        root.query = "";
        root.armedIndex = -1;
        armTimer.stop();
    }

    function toggle(mon) {
        if (root.open)
            root.hide();
        else
            root.show(mon);
    }

    /** Step the selection by `delta`, dropping any armed state so the two agree. */
    function move(delta) {
        var n = root.results.length;
        root.armedIndex = -1;
        armTimer.stop();
        root.selected = Math.max(0, Math.min(n - 1, root.selected + delta));
    }

    /**
     * A new query is a new list: back to the top, and disarmed. Leaving the armed
     * index alone here would be a bug — it indexes `results`, so a filter that
     * drops the armed action would silently re-point it at whatever moved into
     * that slot, and the second Enter would fire something the user never picked.
     */
    function setQuery(text) {
        root.query = text;
        root.selected = 0;
        root.armedIndex = -1;
        armTimer.stop();
    }

    /** Run the action, and close: the strip is a glance, not a place to stay. */
    function run(a) {
        if (!a)
            return;
        if (a.dispatch && a.dispatch.length)
            Hyprland.dispatch(a.dispatch);
        else
            Quickshell.execDetached(a.argv);
        root.hide();
    }

    /**
     * Enter on the selected action. A safe one fires outright; a destructive one
     * arms on the first press and fires on the second inside `armWindow`, clearing
     * the armed state before it runs so it cannot outlive the close.
     */
    function armOrAccept() {
        var a = root.current;
        if (!a)
            return;
        if (!a.confirm) {
            root.run(a);
            return;
        }
        if (root.armedIndex === root.selected) {
            root.armedIndex = -1;
            armTimer.stop();
            root.run(a);
        } else {
            root.armedIndex = root.selected;
            armTimer.restart();
        }
    }

    Timer {
        id: armTimer
        interval: root.armWindow
        repeat: false
        onTriggered: root.armedIndex = -1
    }
}