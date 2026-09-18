pragma Singleton
import QtQuick
import Quickshell

/**
 * Surface-lifecycle bus for the shell's manual eviction door. Each pill connects
 * to `unloadClosedRequested` and drops its own closed surfaces when it fires, so
 * the `unloadAll` IPC only emits and every live pill answers.
 *
 * A signal rather than a registry of pill objects: pills are per-monitor Variants
 * delegates, so a monitor hotplug or an overlay rebuild destroys and recreates
 * them, and a stored object reference would go stale with no cleanup hook. A
 * connection dies with its receiver, so there is nothing to unregister and the
 * bus never needs to know how many monitors exist.
 *
 * This exists because memory saver off means no tail at all — the sweep in
 * Pill.qml never fires — which left "until restart" as the only way to hand that
 * memory back. The IPC makes it a command instead.
 */
Singleton {
    id: root

    /**
     * Fired by `unloadClosed()`. Receivers drop every closed surface right now,
     * leaving the surface on screen and any running timer alone (see
     * `Pill.unloadClosedSurfaces`). Idempotent: a second emit finds nothing left.
     */
    signal unloadClosedRequested()

    /**
     * Ask every pill to drop its closed surfaces immediately, regardless of how
     * much of its tier tail is left. Synchronous — the drops land before this
     * returns — and safe to call from anywhere, including repeatedly.
     */
    function unloadClosed() {
        root.unloadClosedRequested();
    }
}
