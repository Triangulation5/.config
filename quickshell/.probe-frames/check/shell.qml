import QtQuick
import Quickshell

/**
 * Compile check for the edited files: `Qt.createComponent` parses and resolves
 * a file without instantiating it, so no windows, IPC or dispatches are touched.
 * Reports each file's status to check.txt (console.log does not surface in the
 * headless run's log file).
 */
ShellRoot {
    readonly property string root: Quickshell.env("HOME") + "/.config/quickshell/.probe-frames/shellcopy/"
    readonly property string reportPath: Quickshell.env("HOME") + "/.config/quickshell/.probe-frames/check.txt"

    function check(rel) {
        const c = Qt.createComponent("file://" + root + rel);
        const name = rel.split("/").pop();
        return name + ": status=" + c.status
            + (c.status === Component.Error ? "\n    ERRORS: " + c.errorString() : "  ok");
    }

    Component.onCompleted: {
        const out = [
            check("modules/pill/Pill.qml"),
            check("modules/pill/surfaces/PillSurface.qml"),
            check("modules/pill/widgets/wallpaper/Wallpaper.qml"),
            check("modules/pill/HoverFace.qml")
        ];
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"",
            "sh", out.join("\n") + "\n", reportPath]);
    }

    Timer {
        interval: 900
        running: true
        onTriggered: Qt.quit()
    }
}
