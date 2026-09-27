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
 * The top edge has exactly one presentation at a time. The pill is the shell;
 * the minimal DWM-style bar (`Flags.barEnabled`, toggled from Settings) is the
 * light alternative, and while it is on the pill is not built at all. Both sit
 * in LazyLoaders loaded by URL rather than as direct children: a hidden item
 * tree is still an item tree, and an import of the other module would compile
 * its whole tree besides. The inactive branch is neither instantiated nor
 * compiled. Flipping the flag tears one down and builds the other; that is rare
 * and synchronous, and nothing else in the shell is affected (the settings
 * window that flips it is a sibling that stays).
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
    LazyLoader {
        id: pillMode
        active: !Flags.barEnabled
        source: Qt.resolvedUrl("modules/pill/PillRoot.qml")
    }

    LazyLoader {
        id: barMode
        active: Flags.barEnabled
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
