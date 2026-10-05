pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Keeps `hypr/modules/style.lua` in step with `Flags.barEnabled`.
 *
 * The two live on opposite sides of a process boundary. The flag is the shell's
 * half — what the bar and the pill read, persisted in flags.json, flipped by the
 * settings app, the `bar` IPC target and the keybind. `style.lua` is the
 * compositor's half: `monitors.lua` and `decorations.lua` require it at config
 * load to decide the workspace count, the window rounding and whether the
 * animations run at all. Nothing connects them on its own, so switching the bar
 * used to leave the compositor still configured as if nothing had happened —
 * round corners and a fifth workspace, with a dwm bar across the top.
 *
 * The flag is the source of truth and the file follows it, never the other way
 * round. That direction is the whole point: the file is derived output, and a
 * derived output that can argue with its input is not one.
 *
 * So this mirrors the flag, the way `GameMode` mirrors `Flags.gameMode` into
 * `gamemode.sh`, and it follows that service in the two ways that matter:
 *
 *   - It reconciles on startup rather than only on change. A shell restarted
 *     while the bar was on never sees the flag *change*, so a service that only
 *     listened for changes would leave `style.lua` describing the shell that
 *     died. `Component.onCompleted` runs the check unconditionally, which is
 *     what makes the state survive a crash, a `qs` restart or a reboot of the
 *     shell without the user doing anything about it.
 *
 *   - It writes the file rather than asking Hyprland to re-read it. `gamemode.sh`
 *     pushes its values live through `hl.config eval` precisely to avoid a
 *     reload's flicker, and the honest version of that here is to leave the
 *     running compositor alone: the file is made correct for the *next*
 *     Hyprland start, and the user reloads when they want the corners to square
 *     off. A reload triggered from a keypress is a far worse interruption than
 *     one they asked for, and it would also reset the compositor mid-transition
 *     while the shell was still animating.
 *
 * A missing file is not an error and not a reason to do nothing: it is written
 * from the same template it would have had. A fresh install, or a config that
 * never had the module, gets a correct one rather than a bar toggle that
 * silently does half its job. The write is anchored on the `dwmStyle` key rather
 * than on the file's contents, so a `style.lua` the user has since annotated
 * keeps its comments and any other keys they have added.
 */
Singleton {
    id: root

    readonly property bool active: Flags.barEnabled

    /**
     * True when the compositor is in dwm style, i.e. when the bar is off and
     * `style.lua` says `dwmStyle = true`.
     *
     * The QML half of that decision, for surfaces that have to change shape to
     * match: `dwmStyle` is a compositor-side setting the shell only ever
     * *writes*, so a lockscreen popup that squared off with the desktop would
     * otherwise keep its rounded corners in a session with no rounded anything
     * on it. Reading it off the same flag `style.lua` is derived from is what
     * keeps the two halves from disagreeing.
     *
     * Same polarity as `wanted` below, deliberately. That is the word this
     * service writes into `style.lua`, so the two must agree: the file says
     * "dwm style on" exactly when the bar flag is on, and a QML surface
     * squaring off has to square off in the same sessions the compositor does.
     */
    readonly property bool dwmStyle: Flags.barEnabled

    readonly property string stylePath: Quickshell.env("HOME") + "/.config/hypr/modules/style.lua"

    /**
     * What the file is meant to say, as a word Lua reads.
     *
     * Read off `Flags.barEnabled` rather than off `active` so the chain between
     * the flag and the word is one binding rather than two. That matters only in
     * combination with the deferred write below, where the value is read at the
     * moment the process is actually built.
     */
    readonly property string wanted: Flags.barEnabled ? "true" : "false"

    /** A flip that landed while a write was in flight; one more pass picks it up. */
    property bool again: false

    /** Serialised, so a burst of flips costs one write with the last answer. */
    onWantedChanged: root.write()

    Component.onCompleted: root.write()

    /**
     * Ask for the file to be brought into line.
     *
     * The work is deferred a turn on purpose. `wanted` is a binding on a flag
     * that lives in another object, and a change handler runs before the binding
     * that reads it has necessarily been re-evaluated — so writing the file from
     * inside the handler captured the *previous* value, and every flip landed one
     * behind: turning the bar off left `dwmStyle = true` in the file, and the
     * error only showed up as a compositor that was configured for a mode the
     * shell had already left. Letting the turn finish first means the value read
     * is the one the flag is actually holding.
     */
    function write() {
        if (!proc.running) {
            Qt.callLater(root.writeNow);
            return;
        }
        root.again = true;
    }

    function writeNow() {
        if (proc.running) {
            root.again = true;
            return;
        }
        proc.command = ["sh", "-c", root.scriptArg()];
        proc.running = true;
    }

    /**
     * The write itself, in sh so it needs nothing from the shell's environment.
     * Creates the directory and the file if either is absent, and only touches
     * `dwmStyle` when it is not already what we want — so a flip that already
     * matches writes nothing at all.
     *
     * A function rather than a binding: the script text contains literal braces,
     * and QML reads a `{` inside a binding expression as the start of an object
     * literal rather than as part of a string it already parsed.
     */
    function scriptArg() {
        var dir = stylePath.substring(0, stylePath.lastIndexOf("/"));
        var w = wanted;
        return [
            "set -e",
            "dir=" + JSON.stringify(dir),
            "file=" + JSON.stringify(stylePath),
            "mkdir -p \"$dir\"",
            "[ -f \"$file\" ] || printf '%s\\n' 'return {' '    dwmStyle = " + w + ",' '}' > \"$file\"",
            "grep -Eq '^[[:space:]]*dwmStyle[[:space:]]*=' \"$file\" || printf '%s\\n' '    dwmStyle = " + w + ",' >> \"$file\"",
            "sed -i -E 's/^([[:space:]]*dwmStyle[[:space:]]*=[[:space:]]*)(true|false)/\\1" + w + "/' \"$file\""
        ].join("; ");
    }

    /**
     * One write at a time. The command is rebuilt from `scriptArg()`, which reads
     * `active` as it is at the moment it is called, so the pass after a flip that
     * landed mid-write picks up whatever the flag says *now* rather than what it
     * said when the queue was set — the last answer wins without queueing more
     * than one.
     */
    Process {
        id: proc
        onExited: {
            if (!root.again)
                return;
            root.again = false;
            root.write();
        }
    }
}