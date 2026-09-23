import QtQuick
import Quickshell

/**
 * Reports the object tree for the alias probe: where a subclass's declared
 * children land, and whether the base's own body child stays put. Written to
 * report.txt with execDetached because console.log does not surface in the
 * headless run's log file.
 */
ShellRoot {
    readonly property string reportPath: Quickshell.env("HOME") + "/.config/quickshell/.probe-frames/wrap/report.txt"

    function nameOf(o) {
        return o.objectName && o.objectName.length > 0 ? o.objectName : "<none>";
    }

    function listOf(kids) {
        const out = [];
        for (let i = 0; i < kids.length; i++)
            out.push(nameOf(kids[i]));
        return "[" + out.join(", ") + "]";
    }

    function report() {
        const s = child;
        const lines = [];
        lines.push("has fadeWrap: " + (s.fadeWrap !== undefined));
        lines.push("child.children: " + s.children.length + " " + listOf(s.children));
        lines.push("wrap.children: " + s.fadeWrap.children.length + " " + listOf(s.fadeWrap.children));
        lines.push("wrap.parent === child: " + (s.fadeWrap.parent === s));
        for (let i = 0; i < s.children.length; i++)
            lines.push("child[" + i + "] is wrap: " + (s.children[i] === s.fadeWrap));
        lines.push("wrap.width === child.width: " + (s.fadeWrap.width === s.width)
            + " (" + s.fadeWrap.width + " vs " + s.width + ")");
        return lines.join("\n") + "\n";
    }

    Window {
        width: 80
        height: 40
        visible: true

        SurfChild {
            id: child
            anchors.fill: parent
        }
    }

    Component.onCompleted: Quickshell.execDetached(["sh", "-c",
        "printf '%s' \"$1\" > \"$2\"", "sh", report(), reportPath])

    Timer {
        interval: 400
        running: true
        onTriggered: Qt.quit()
    }
}
