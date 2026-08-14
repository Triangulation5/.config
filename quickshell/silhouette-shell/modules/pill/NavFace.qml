import QtQml
import Quickshell.Services.SystemTray

/**
 * Hover-face navigation for the pill: the ordered list of focusable faces
 * (media, minimized apps, tray, clock) and the arrow/return/back handlers that
 * walk them, descending into the minimized and tray icon rows at the edges.
 * All pill state lives on the host (`host`).
 */
QtObject {
    id: face

    required property var host

    readonly property var faceTargets: {
        var out = [];
        if (host.hasMedia) out.push("media");
        if (host.minimizedRow.count > 0) out.push("minimized");
        if (SystemTray.items.values.length > 0) out.push("tray");
        out.push("clock");
        return out;
    }
    readonly property int faceCount: faceTargets.length

    function faceMove(dir) {
        if (host.surfaceOpen || host.mode !== "hover" || faceCount < 2)
            return false;
        if (host.faceFocus < 0 || host.faceFocus >= faceCount)
            host.faceFocus = 0;
        var key = faceTargets[host.faceFocus];
        /**
         * While the ring sits on a per-icon widget, arrows walk its icons and
         * step out to the neighbouring face target at the edges.
         */
        if (key === "minimized") {
            if (host.minimizedRow.focusIndex < 0)
                host.minimizedRow.focusIndex = 0;
            if (dir < 0 && host.minimizedRow.focusIndex === 0)
                host.faceFocus = (host.faceFocus - 1 + faceCount) % faceCount;
            else if (dir > 0 && host.minimizedRow.focusIndex === host.minimizedRow.count - 1)
                host.faceFocus = (host.faceFocus + 1) % faceCount;
            else
                host.minimizedRow.moveFocus(dir);
            return true;
        }
        if (key === "tray") {
            var nItems = SystemTray.items.values.length;
            if (host.trayRow.focusIndex < 0)
                host.trayRow.focusIndex = 0;
            if (dir < 0 && host.trayRow.focusIndex === 0)
                host.faceFocus = (host.faceFocus - 1 + faceCount) % faceCount;
            else if (dir > 0 && host.trayRow.focusIndex === nItems - 1)
                host.faceFocus = (host.faceFocus + 1) % faceCount;
            else
                host.trayRow.moveFocus(dir);
            return true;
        }
        host.faceFocus = (host.faceFocus + dir + faceCount) % faceCount;
        var landed = faceTargets[host.faceFocus];
        if (landed === "minimized" && host.minimizedRow.focusIndex < 0)
            host.minimizedRow.focusIndex = 0;
        if (landed === "tray" && host.trayRow.focusIndex < 0)
            host.trayRow.focusIndex = 0;
        return true;
    }

    function faceActivate() {
        if (host.surfaceOpen || host.mode !== "hover")
            return false;
        var key = host.faceFocus >= 0 && host.faceFocus < faceCount ? faceTargets[host.faceFocus] : "clock";
        if (key === "media") {
            host.requestSurface("media");
        } else if (key === "minimized") {
            if (host.minimizedRow.focusIndex < 0)
                host.minimizedRow.focusIndex = 0;
            host.minimizedRow.activate();
        } else if (key === "tray") {
            if (host.trayRow.focusIndex < 0)
                host.trayRow.focusIndex = 0;
            host.trayRow.activate();
        } else {
            host.openCalendarAt(null);
        }
        return true;
    }

    /**
     * Escape/Backspace on the hover face: unpin if held and collapse the pill
     * back to rest. Returns true when the face was showing and consumed it.
     */
    function faceBack() {
        if (host.surfaceOpen || host.mode !== "hover")
            return false;
        if (host.pinned)
            host.pinned = false;
        host.hoverLatch = false;
        host.faceFocus = -1;
        return true;
    }
}
