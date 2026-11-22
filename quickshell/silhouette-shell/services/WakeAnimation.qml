pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wake-up animation controller for Power Menu -> Sleep.
 *
 * When the user selects "Sleep" from the power menu, power.sh captures each
 * monitor to $XDG_RUNTIME_DIR/silhouette-wake-<output>.png, waits for grim to
 * finish, and writes "1" to $XDG_RUNTIME_DIR/silhouette-wake-active before
 * suspending.
 *
 * Lifecycle:
 *  1. Before sleep (onLockRequested / onSuspending): if the marker is "1",
 *     arm `active` and `primed` so every LockSurface mounts with the captured
 *     pre-suspend screenshot as its backdrop and a solid black cover at
 *     progress 0 — preventing any flash of the lock screen when the display
 *     powers back on.
 *  2. On resume (onResumed): consume the marker so non-menu suspends (lid
 *     close, idle, bare systemctl suspend) never replay it, then start the
 *     bottom-center circular grow reveal across all monitors.
 *  3. On animation complete (finish): drop `playing` / `primed` while keeping
 *     `active` so the lock backdrop stays on the pre-suspend capture until
 *     unlock.
 *  4. On unlock (disarm): clear state and sweep silhouette-wake-*.png.
 */
Singleton {
    id: root

    /** True while a power-menu sleep session is using the wake capture. */
    property bool active: false

    /** True while waiting for resume (screen covered in black at progress 0). */
    property bool primed: false

    /** True while the bottom-center circular grow reveal is animating. */
    property bool playing: false

    /** Emitted once the display has woken and LockSurfaces should start the grow. */
    signal revealStarted()

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string markerPath: runtimeDir + "/silhouette-wake-active"

    property bool markerPresent: false

    FileView {
        id: markerFile
        path: root.markerPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            var activeFlag = markerFile.text().trim() === "1";
            root.markerPresent = activeFlag;
            if (activeFlag && Flags.wakeAnimation && !root.primed && !root.playing) {
                root.active = true;
                root.primed = true;
                root.playing = false;
            }
        }
        onFileChanged: markerFile.reload()
        onLoadFailed: {
            root.markerPresent = false;
            markerFile.setText("0");
        }
    }

    Process { id: wakeCleaner }

    function hasMarker(): bool {
        markerFile.reload();
        return root.markerPresent;
    }

    function consumeMarker(): void {
        root.markerPresent = false;
        markerFile.setText("0");
    }

    /** Returns the pre-suspend screenshot URL for a given output, or "". */
    function shotUrlFor(screenName: string): string {
        if (!root.active || !screenName || screenName.length === 0)
            return "";
        return "file://" + root.runtimeDir + "/silhouette-wake-" + screenName + ".png";
    }

    /**
     * Arm the black pre-wake cover before the system enters sleep, only when
     * power.sh suspend left the wake marker behind.
     */
    function prepareForSleep(): bool {
        if (!Flags.wakeAnimation)
            return false;
        if (root.primed)
            return true;
        if (!root.hasMarker())
            return false;
        root.active = true;
        root.primed = true;
        root.playing = false;
        return true;
    }

    /**
     * Called on PrepareForSleep(false). Returns true if a power-menu wake
     * reveal should play.
     */
    function onResumed(): bool {
        if (!Flags.wakeAnimation) {
            if (root.hasMarker())
                root.consumeMarker();
            root.disarm();
            return false;
        }
        if (!root.primed && !root.hasMarker()) {
            root.disarm();
            return false;
        }
        root.consumeMarker();
        root.active = true;
        root.primed = true;
        root.playing = false;
        return true;
    }

    /** Triggered by LockRoot after the brief DPMS settle + renderer kick. */
    function startReveal(): void {
        if (!root.active)
            return;
        root.primed = false;
        root.playing = true;
        root.revealStarted();
    }

    /** Called when the circular grow animation finishes. */
    function finish(): void {
        root.primed = false;
        root.playing = false;
    }

    /** Called on session unlock (or when no wake animation applies). */
    function disarm(): void {
        root.active = false;
        root.primed = false;
        root.playing = false;
        wakeCleaner.running = false;
        wakeCleaner.command = ["sh", "-c", "rm -f \"$1\"/silhouette-wake-*.png", "sh",
            root.runtimeDir];
        wakeCleaner.running = true;
    }
}
