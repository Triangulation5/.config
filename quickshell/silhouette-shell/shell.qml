import QtQuick
import Quickshell
import Quickshell.Io

import qs.services
import qs.modules.lock
import qs.modules.screencorner
import qs.modules.launcher
import qs.modules.reload
import qs.modules.settingsapp

/**
 * Shell entry point — a pure composition root. Each daemon is a self-contained
 * module that also owns its IPC surface (`qs ipc call pill|bar|lock|launcher|settings ...`):
 * the pill's surface routing lives in PillRoot, the bar's in BarRoot, the lock
 * trigger in LockRoot and the standalone launcher's show/hide/toggle in
 * LauncherRoot. Adding or removing a module never touches this file.
 *
 * The top edge still has exactly one presentation at a time. The pill is the
 * shell; the minimal DWM-style bar (`Flags.barEnabled`, toggled from Settings) is
 * the light alternative. Both sit in LazyLoaders loaded by URL rather than as
 * direct children: a hidden item tree is still an item tree, and an import of
 * the other module would compile its whole tree besides. The inactive branch is
 * neither instantiated nor compiled.
 *
 * What changed is the seam between them. Neither loader keys off the flag any
 * more; both read `BarSwap`, which holds the clock the swap is played against.
 * So the pill's tree survives for as long as it still has somewhere to be seen
 * — long enough to fly up off the top edge the way it does for a fullscreen
 * window — and the bar's is built as its strip starts to fall. Without that the
 * swap was a hard cut with a blank stretch of screen across the gap, because
 * under a plain `!Flags.barEnabled` the pill was already gone before it could
 * move. Once the swap has landed exactly one of the two is resident again, and
 * nothing else in the shell is affected (the settings window that flips it is a
 * sibling that stays).
 *
 * The root also owns one IPC surface of its own rather than leaving it to a
 * module: the minimal bar's toggle. It cannot live in `modules/bar` with the rest
 * of that module, because the bar is built only while `Flags.barEnabled` is set —
 * and the bind that switches it on has to reach a target that outlives the very
 * tree it is about to build. When the bar is up it is the pill's routes that are
 * gone, so whichever of the two carries the switch would be the one missing
 * exactly when it is needed.
 *
 * `SettingsApp` is the Silhouette Settings dialog, moved in from its own config
 * and still a module of its own: it builds the FloatingWindow this process hosts
 * when it is first opened and tears it down again five seconds after it closes,
 * so the window that edits the flags and the shell that reads them are one
 * instance rather than two watching the same file and a dialog nobody opened
 * costs nothing. It answers to `settings` like the others; its tree, its pages
 * and its own palette are unchanged — see `modules/settingsapp/`.
 */

ShellRoot {
    /**
     * The bar's other half. `BarMode` mirrors `Flags.barEnabled` into
     * `hypr/modules/style.lua` so the compositor's half of the switch follows the
     * shell's, and nothing else here has to know that file exists. Naming it is
     * all that is required — a QML singleton is built the first time anything
     * reaches for it and lives as long as the engine does, so this one line is
     * what makes the mirror run for the session, including on a shell that
     * started with the bar already on.
     */
    Component.onCompleted: BarMode.active

    LazyLoader {
        id: pillMode
        active: BarSwap.pillWanted
        source: Qt.resolvedUrl("modules/pill/PillRoot.qml")
    }

    LazyLoader {
        id: barMode
        active: BarSwap.barWanted
        source: Qt.resolvedUrl("modules/bar/BarRoot.qml")
    }

    IpcHandler {
        target: "bar"

        function toggle(): void { Flags.barEnabled = !Flags.barEnabled; }
        function enable(): void { Flags.barEnabled = true; }
        function disable(): void { Flags.barEnabled = false; }
    }

    LockRoot { id: lockRoot }
    ScreenCornerRoot { id: cornerRoot }
    LauncherRoot { id: launcherRoot }
    ReloadPopup { id: reloadRoot }
    SettingsApp { id: settingsApp }
}
