pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Game mode: one flag that strips Hyprland's eye-candy and quiets the desktop for
 * gaming or deep focus. Entering snapshots the focus flags, forces do-not-disturb
 * and keep-awake on, pauses the visualizer, clears the pill's lazily built
 * surfaces, and runs the visual strip; leaving restores each to what it was
 * before. The strip itself lives in gamemode.sh so the original decoration values
 * survive a pill restart. `Flags.gameMode` is the single source of truth, flipped
 * by the mixer chip, the keybind, or IPC.
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

    onActiveChanged: active ? root.enter() : root.leave()

    function enter() {
        Flags.gamePrevDnd = Flags.dnd;
        Flags.gamePrevViz = Flags.musicViz;
        Flags.gamePrevAwake = Flags.keepAwake;
        Flags.dnd = true;
        Flags.musicViz = false;
        Flags.keepAwake = true;
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
        root.run("off");
        Flags.dnd = Flags.gamePrevDnd;
        Flags.musicViz = Flags.gamePrevViz;
        Flags.keepAwake = Flags.gamePrevAwake;
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
