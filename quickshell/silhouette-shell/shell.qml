import QtQuick
import Quickshell

import qs.modules.pill
import qs.modules.lock
import qs.modules.screencorner
import qs.modules.launcher

/**
 * Shell entry point — a pure composition root. Each daemon is a self-contained
 * module that also owns its IPC surface (`qs ipc call pill|lock|launcher ...`):
 * the pill's surface routing lives in PillRoot, the lock trigger in LockRoot and
 * the standalone launcher's show/hide/toggle in LauncherRoot. Adding or removing
 * a module never touches this file.
 */

ShellRoot {
    PillRoot { id: pillRoot }
    LockRoot { id: lockRoot }
    ScreenCornerRoot { id: cornerRoot }
    LauncherRoot { id: launcherRoot }
}
