import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.services
import qs.config
import qs.modules.bar.workspaces // For CompositorData
import "Singletons"

PanelWindow {
    id: screenCorners

    property var monitor: null
    property bool activeWindowFullscreen: false

    function updateFullscreen() {
        const mon = AxctlService.monitorFor(screen);
        if (mon)
            monitor = mon;

        if (!monitor) {
            activeWindowFullscreen = false;
            return;
        }

        const activeWorkspaceId = monitor.activeWorkspace.id;
        const monId = monitor.id;

        // Check active toplevel first (fast path)
        const toplevel = ToplevelManager.activeToplevel;
        if (toplevel
                && toplevel.fullscreen
                && AxctlService.focusedMonitor
                && AxctlService.focusedMonitor.id === monId) {
            activeWindowFullscreen = true;
            return;
        }

        // Check all windows on this monitor (robust path)
        const wins = CompositorData.windowList;
        for (let i = 0; i < wins.length; i++) {
            if (wins[i].monitor === monId
                    && wins[i].fullscreen
                    && wins[i].workspace.id === activeWorkspaceId) {
                activeWindowFullscreen = true;
                return;
            }
        }

        activeWindowFullscreen = false;
    }

    Connections {
        target: AxctlService.monitors

        function onValuesChanged() {
            screenCorners.updateFullscreen();
        }
    }

    Connections {
        target: CompositorData

        function onWindowListChanged() {
            screenCorners.updateFullscreen();
        }
    }

    Connections {
        target: AxctlService

        function onFocusedMonitorChanged() {
            screenCorners.updateFullscreen();
        }
    }

    Component.onCompleted: updateFullscreen()

    visible: Config.theme.enableCorners
             && Config.roundness > 0
             && !activeWindowFullscreen

    color: "transparent"

    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:screenCorners"
    WlrLayershell.layer: WlrLayer.Overlay

    mask: Region {
        item: null
    }

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Shared corner state
    readonly property bool gameMode: Flags.gameMode

    // Match the pill/lockscreen surface.
    readonly property color cornerColor: Theme.capsule

    // Morph tuning
    readonly property int morphDuration: 700

    // Inside bezel shadow only
    readonly property bool innerShadow: true
    readonly property color innerShadowColor: Qt.rgba(0, 0, 0, 0.28)
    readonly property real innerShadowSize: 8

    ScreenCornersContent {
        id: cornersContent

        anchors.fill: parent

        hasFullscreenWindow: screenCorners.activeWindowFullscreen

        cornerColor: screenCorners.cornerColor

        // Game mode evaporation
        gameMode: screenCorners.gameMode

        // Morph timing
        morphDuration: screenCorners.morphDuration

        // Inner edge shadow
        innerShadow: screenCorners.innerShadow
        innerShadowColor: screenCorners.innerShadowColor
        innerShadowSize: screenCorners.innerShadowSize
    }
}
