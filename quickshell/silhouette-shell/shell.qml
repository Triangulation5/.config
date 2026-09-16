import QtQuick
import Quickshell

import qs.modules.pill
import qs.modules.lock
import qs.modules.screencorner
import qs.modules.launcher
import qs.modules.reload
import qs.modules.settingsapp

/**
 * Shell entry point — a pure composition root. Each daemon is a self-contained
 * module that also owns its IPC surface (`qs ipc call pill|lock|launcher|settings ...`):
 * the pill's surface routing lives in PillRoot, the lock trigger in LockRoot and
 * the standalone launcher's show/hide/toggle in LauncherRoot. Adding or removing
 * a module never touches this file.
 *
 * `SettingsApp` is the Silhouette Settings dialog, moved in from its own config
 * and still a module of its own: a FloatingWindow this process hosts, so the
 * window that edits the flags and the shell that reads them are one instance
 * rather than two watching the same file. It answers to `settings` like the
 * others; its tree, its pages and its own palette are unchanged — see
 * `modules/settingsapp/`.
 */

ShellRoot {
    PillRoot { id: pillRoot }
    LockRoot { id: lockRoot }
    ScreenCornerRoot { id: cornerRoot }
    LauncherRoot { id: launcherRoot }
    ReloadPopup { id: reloadRoot }
    SettingsApp { id: settingsApp }
}
