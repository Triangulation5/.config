pragma Singleton

import QtQuick
import qs.services

/**
 * Timers: how long the shell waits. The pill's memory saver (its on/off switch
 * and the base tail it counts from, plus how often the sweep looks for a closed
 * surface to evict), the hover grace before the pill collapses, how long an
 * overlay stays up, and how long a notification popup lives.
 *
 * The tail used to be one flat number, timed from a surface's last open. It is
 * now the base of a small tier table in Pill.qml — the heaviest surfaces
 * (wallpaper, mixer) are reclaimed at this value, everything else at double —
 * and it is counted from the moment a surface closes rather than from when it
 * was last opened, so a surface you stared at for a minute gets the same tail as
 * one you flicked past. Memory saver off means no tail at all: every closed
 * surface stays resident for the session, and the only way to hand that memory
 * back is `qs ipc call pill unloadAll`, which drops every closed surface on
 * every monitor on the spot (`Surfaces.unloadClosed()`), leaving what is on
 * screen, a running timer and a pending polkit prompt alone. There is a row for
 * it right under the saver's switch.
 *
 * Game mode outranks the whole schedule: entering it clears the closed surfaces
 * immediately, and for as long as it is on a closed surface is reclaimed at the
 * game-mode tail whatever its tier — even with the saver off — with the sweep held
 * to the shorter of the cleanup sweep and the game-mode one. The rows below
 * describe the ordinary session; the pair after them is that override, so the
 * schedule the mode runs on is set from the same card the ordinary one is.
 *
 * That row is why this page imports the shell's `qs.services` and no other page
 * does. Everywhere else here edits a file and lets the shell notice, but a button
 * that hands memory back has to act on the running shell, which is the same
 * process this app is hosted in — so it calls the shell's own registry directly
 * rather than shelling out to a `qs ipc call` that would have to guess which
 * instance to talk to.
 *
 * The surface idle timeout used to sit on the Pill shape page among forty-eight
 * sizes. It is a duration, not a shape, and it is the one setting here that a
 * person is likely to reach for ("the pill keeps swallowing my Escape") — so it
 * moved to where the other timeouts are. Same flag, same default.
 */
QtObject {
    readonly property string name: "Timers"
    readonly property string icon: "\u25F4"
    readonly property string keywords: "timers timeout timeouts duration durations wait delay grace sweep hold popup idle lazy eviction expires surface memory saver ram resident unload reclaim closed free"

    readonly property var groups: [
        { card: "Pill", rows: [
            { key: "memorySaver", type: "toggle", label: "Memory saver",
              caption: "Free a closed surface once its tail has passed (off = keep every surface resident until pill unloadAll)", reset: true },
            // The one row in this app whose subject is the running shell rather
            // than a file: it runs the same function the `pill unloadAll` IPC
            // does, in this process, so there is no `qs ipc call` subprocess and
            // no guessing which instance to talk to. It carries a key only so a
            // rail search can ring it (Reset skips rows with no `reset`).
            { key: "unloadAll", type: "action", label: "Unload closed surfaces",
              button: "Unload", done: "Unloaded",
              caption: "Drop every closed surface on every monitor now instead of waiting out its tail. The open surface, a running timer and a pending polkit prompt are left alone",
              action: function () { Surfaces.unloadClosed(); } },
            { key: "pillSurfaceIdleTimeout", type: "slider", label: "Surface idle timeout",
              min: 10, max: 60, step: 1, unit: "s",
              caption: "Base tail: the heaviest surfaces are freed at this, everything else at double", reset: 12 },
            { key: "pillCleanupSec", type: "slider", label: "Cleanup sweep",
              min: 2, max: 60, step: 1, unit: "s",
              caption: "How often the pill looks for closed surfaces to evict", reset: 10 },
            // Game mode's override of the two rows above: while the mode is on,
            // Pill.qml frees a closed surface at this one tail whatever its tier
            // and runs the sweep at most this often, even with the saver off. Two
            // rows rather than a read-only line, because the override is a setting
            // in its own right — the numbers Pill.qml applies are the ones chosen
            // here.
            { key: "pillGameUnloadMs", type: "slider", label: "Game-mode tail",
              min: 0, max: 5000, step: 100, unit: "ms",
              caption: "While game mode is on, how long a closed surface lingers before it is freed (0 frees it at the very next sweep, which can clip its close)", reset: 1000 },
            { key: "pillGameSweepSec", type: "slider", label: "Game-mode sweep",
              min: 1, max: 10, step: 1, unit: "s",
              caption: "How often the pill looks for closed surfaces to free while game mode is on; the cleanup sweep above still applies when it is the shorter of the two", reset: 2 },
            { key: "pillHoverGraceMs", type: "slider", label: "Hover grace",
              min: 0, max: 1000, step: 50, unit: "ms",
              caption: "How long the pill waits before collapsing after the pointer leaves", reset: 300 }
        ]},
        { card: "Overlays", rows: [
            { key: "osdHoldMs", type: "slider", label: "Overlay hold",
              min: 500, max: 5000, step: 100, unit: "ms",
              caption: "How long a volume, brightness or track overlay stays up", reset: 1800 }
        ]},
        { card: "Notifications", rows: [
            { key: "notifMs", type: "slider", label: "Popup time",
              min: 1000, max: 20000, step: 500, unit: "ms",
              caption: "How long a notification popup stays on screen", reset: 6000 },
            { key: "notifLowMs", type: "slider", label: "Low urgency",
              min: 1000, max: 20000, step: 500, unit: "ms",
              caption: "The same, for a notification that marks itself low", reset: 4000 }
        ]}
    ]
}
