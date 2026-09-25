pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Game mode: one flag that strips Hyprland's eye-candy and quiets the desktop for
 * gaming or deep focus. Entering clears the pill's lazily built surfaces and runs
 * the visual strip; leaving runs it the other way. The strip itself lives in
 * gamemode.sh so the original decoration values survive a pill restart.
 * `Flags.gameMode` is the single source of truth, flipped by the mixer chip, the
 * keybind, or IPC.
 *
 * The three focus flags it holds — do-not-disturb, keep-awake and the pill's
 * visualizer — are held *here* rather than written. `dnd`, `keepAwake` and
 * `visualizer` below are what the session should see while the mode is on, and
 * everything that cares reads those instead of the raw flag. Writing the flags
 * instead, as this service used to, put the mode's values into flags.json as if
 * the user had chosen them, kept honest only by a snapshot restored on the way
 * out — so a shell that was killed, crashed or restarted while the mode was on
 * left `musicViz: false` behind with the snapshot gone with the process, and the
 * visualizer stayed off until it was switched back on by hand. A held value
 * cannot outlive the mode, because there is nothing persisted to restore.
 *
 * A hold is released the moment the flag under it changes, which is how a user
 * toggles DND or the visualizer *during* the mode: the change is theirs, so the
 * mode stops overruling that one flag. The quick chips read `GameMode.*` and write
 * back the opposite of what they show, so a press is still a press; the settings
 * surfaces deliberately keep reading `Flags.*`, where a toggle shows the choice
 * rather than the mode's temporary overrule of it.
 *
 * The memory side is two halves that meet here. This service does the one-shot
 * *clear*: every pill drops its closed surfaces at once (the same door the
 * Timers page's "Unload closed surfaces" button and `pill unloadAll` use). The
 * *harsh* half lives in Pill.qml, which reads `Flags.gameMode` and reclaims a
 * closed surface at the next sweep instead of after its tier, with the sweep
 * capped to a couple of seconds — so for as long as the mode lasts the pill keeps
 * handing memory back rather than only doing it once on entry. Both leave the
 * surface on screen, a running timer and a pending polkit prompt alone.
 */
Singleton {
    id: root

    readonly property bool active: Flags.gameMode
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/gamemode.sh"
    property string pending: ""

    /**
     * Whether the mode is still the one holding each focus flag. Cleared by the
     * Connections below the moment the flag changes under it — a change the mode
     * did not make — and on the way out.
     */
    property bool dndHeld: false
    property bool awakeHeld: false
    property bool vizHeld: false

    /**
     * The focus flags as the session should see them: DND on, keep-awake on and
     * the visualizer muted while the mode holds each, and the user's own value
     * otherwise.
     */
    readonly property bool dnd: root.dndHeld || Flags.dnd
    readonly property bool keepAwake: root.awakeHeld || Flags.keepAwake
    readonly property bool visualizer: !root.vizHeld && Flags.musicViz

    /** True while the mode is holding at least one of the three. */
    readonly property bool holding: root.dndHeld || root.awakeHeld || root.vizHeld

    onActiveChanged: active ? root.enter() : root.leave()

    /** A held flag changed under the mode, so that hold is the user's to keep now. */
    Connections {
        target: Flags

        function onDndChanged() { root.dndHeld = false }
        function onKeepAwakeChanged() { root.awakeHeld = false }
        function onMusicVizChanged() { root.vizHeld = false }
    }

    /**
     * A session that starts with the mode already on — a shell restarted while it
     * was held — never sees `active` *change*, so the holds are taken here too
     * rather than only from onActiveChanged. The strip is reapplied with them,
     * which is what the flag saying "on" has always meant.
     */
    Component.onCompleted: if (root.active) root.enter()

    function enter() {
        /** The startup path and the flag change that follows it would otherwise both land here. */
        if (root.holding)
            return;
        root.dndHeld = true;
        root.awakeHeld = true;
        root.vizHeld = true;
        /**
         * Hand back what the desktop was holding for its quick re-opens before
         * the game takes the machine: every pill drops its closed surfaces now,
         * and Pill.qml's sweeper keeps them dropped while the mode lasts. Emitted
         * as a bus signal, so it reaches every monitor's pill without this
         * singleton having to know how many there are.
         */
        Surfaces.unloadClosed();
        root.run("on");
    }

    function leave() {
        root.dndHeld = false;
        root.awakeHeld = false;
        root.vizHeld = false;
        root.run("off");
    }

    function run(arg) {
        if (proc.running) {
            root.pending = arg;
            return;
        }
        proc.command = ["bash", root.script, arg];
        proc.running = true;
    }

    Process {
        id: proc
        onExited: {
            if (root.pending.length === 0)
                return;
            var a = root.pending;
            root.pending = "";
            proc.command = ["bash", root.script, a];
            proc.running = true;
        }
    }
}
