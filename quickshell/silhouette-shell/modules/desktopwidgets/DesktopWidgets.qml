pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.desktopwidgets

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: desktop

        required property var modelData

        readonly property real scaleFactor: Math.max(0.62, Math.min(1.25,
            Math.min(modelData.width / 1600, modelData.height / 900) * Flags.uiScale))
        property var musicWidget: null
        readonly property var activePlayer: Players.active
        readonly property bool hasActivePlayer: activePlayer !== null && activePlayer !== undefined

        function widgetInput(widgetId, inputName) {
            for (var i = 0; i < widgetRepeater.count; i++) {
                var frame = widgetRepeater.itemAt(i);
                if (!frame || frame.modelData.id !== widgetId || !frame.widgetEnabled
                        || !frame.loadedWidget)
                    continue;
                return frame.loadedWidget[inputName] || null;
            }
            return null;
        }

        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "silhouette-desktop-widgets"
        WlrLayershell.layer: DesktopWidgetState.editing ? WlrLayer.Overlay : WlrLayer.Bottom
        WlrLayershell.keyboardFocus: DesktopWidgetState.editing
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        mask: DesktopWidgetState.editing ? fullRegion : interactiveRegion

        Region {
            id: fullRegion
            width: desktop.width
            height: desktop.height
        }
        Region {
            id: interactiveRegion
            Region {
                item: desktop.musicWidget
                    && DesktopWidgetState.musicStyle === "ticket"
                    && desktop.musicWidget.ticketSeekEnabled
                    ? desktop.musicWidget.ticketSeekInput : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.musicWidget
                    && DesktopWidgetState.musicStyle === "ticket"
                    && desktop.musicWidget.ticketTransportEnabled
                    ? desktop.musicWidget.ticketTransportInput : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.musicWidget
                    && DesktopWidgetState.musicStyle === "waveform"
                    && desktop.musicWidget.lineSeekEnabled
                    ? desktop.musicWidget.lineSeekInput : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.musicWidget
                    && DesktopWidgetState.musicStyle === "waveform"
                    && desktop.musicWidget.lineTransportEnabled
                    ? desktop.musicWidget.lineTransportInput : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && (desktop.activePlayer.canTogglePlaying
                    || desktop.activePlayer.canGoPrevious || desktop.activePlayer.canGoNext)
                    ? desktop.widgetInput("musicExpressive", "musicTransportInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && desktop.activePlayer.canSeek
                    && desktop.activePlayer.positionSupported
                    && Players.lengthSec > 0 && !Players.live
                    ? desktop.widgetInput("musicExpressive", "musicSeekInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && (desktop.activePlayer.canTogglePlaying
                    || desktop.activePlayer.canGoPrevious || desktop.activePlayer.canGoNext)
                    ? desktop.widgetInput("musicDisc", "musicTransportInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && desktop.activePlayer.canSeek
                    && desktop.activePlayer.positionSupported
                    && Players.lengthSec > 0 && !Players.live
                    ? desktop.widgetInput("musicDisc", "musicSeekInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && (desktop.activePlayer.canTogglePlaying
                    || desktop.activePlayer.canGoPrevious || desktop.activePlayer.canGoNext)
                    ? desktop.widgetInput("musicDeck", "musicTransportInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && desktop.activePlayer.canSeek
                    && desktop.activePlayer.positionSupported
                    && Players.lengthSec > 0 && !Players.live
                    ? desktop.widgetInput("musicDeck", "musicSeekInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && (desktop.activePlayer.canTogglePlaying
                    || desktop.activePlayer.canGoPrevious || desktop.activePlayer.canGoNext)
                    ? desktop.widgetInput("musicRail", "musicTransportInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && desktop.activePlayer.canSeek
                    && desktop.activePlayer.positionSupported
                    && Players.lengthSec > 0 && !Players.live
                    ? desktop.widgetInput("musicRail", "musicSeekInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && (desktop.activePlayer.canTogglePlaying
                    || desktop.activePlayer.canGoPrevious || desktop.activePlayer.canGoNext)
                    ? desktop.widgetInput("musicPulse", "musicTransportInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.hasActivePlayer && desktop.activePlayer.canSeek
                    && desktop.activePlayer.positionSupported
                    && Players.lengthSec > 0 && !Players.live
                    ? desktop.widgetInput("musicPulse", "musicSeekInput") : null
                intersection: Intersection.Combine
            }
            Region {
                item: DesktopWidgetState.isEnabled("pomodoro")
                    ? desktop.widgetInput("pomodoro", "timerInput") : null
                intersection: Intersection.Combine
            }
        }

        Component.onCompleted: {
            if (Flags.ready)
                DesktopWidgetState.handleFlagsReady();
            Sysmon.desktopOpen = DesktopWidgetState.isCategoryEnabled("System");
            if (DesktopWidgetState.isCategoryEnabled("Weather")
                    || DesktopWidgetState.isEnabled("moon"))
                Weather.needed = true;
        }
        Component.onDestruction: Sysmon.desktopOpen = false

        Connections {
            target: DesktopWidgetState
            function onLayoutChanged() {
                Sysmon.desktopOpen = DesktopWidgetState.isCategoryEnabled("System");
                if (DesktopWidgetState.isCategoryEnabled("Weather")
                        || DesktopWidgetState.isEnabled("moon"))
                    Weather.needed = true;
            }
        }

        Connections {
            target: Flags
            function onReadyChanged() {
                DesktopWidgetState.handleFlagsReady();
            }
        }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: DesktopWidgetState.editing

            Keys.onEscapePressed: DesktopWidgetState.finishEditing()

            Rectangle {
                anchors.fill: parent
                visible: DesktopWidgetState.editing
                color: "#99000000"
                z: 0
            }

            property var draggedFrame: null
            property point pointerStart
            property real dragXStart: 0
            property real dragYStart: 0
            property real dragWidthStart: 0
            property real dragHeightStart: 0
            property bool dragResizing: false

            Repeater {
                id: widgetRepeater
                model: DesktopWidgetState.catalog

                delegate: Item {
                    id: frame

                    required property var modelData

                    property var settings: DesktopWidgetState.widget(frame.modelData.id)
                    readonly property var loadedWidget: widgetLoader.item
                    readonly property bool widgetEnabled: DesktopWidgetState.isEnabled(frame.modelData.id)
                    property real liveX: settings ? settings.x : modelData.x
                    property real liveY: settings ? settings.y : modelData.y
                    property real liveWidth: settings ? settings.w : modelData.w
                    property real liveHeight: settings ? settings.h : modelData.h
                    property bool moving: false
                    property bool resizing: false

                    function clamp(value, lower, upper) {
                        return Math.max(lower, Math.min(upper, value));
                    }

                    function saveGeometry() {
                        DesktopWidgetState.saveGeometry(frame.modelData.id,
                            frame.liveX, frame.liveY, frame.liveWidth, frame.liveHeight);
                    }

                    function syncFromSettings() {
                        if (frame.moving || frame.resizing)
                            return;
                        var currentSettings = DesktopWidgetState.widget(frame.modelData.id);
                        if (!currentSettings)
                            return;
                        frame.settings = currentSettings;
                        frame.liveX = currentSettings.x;
                        frame.liveY = currentSettings.y;
                        frame.liveWidth = currentSettings.w;
                        frame.liveHeight = currentSettings.h;
                    }

                    Connections {
                        target: DesktopWidgetState
                        function onLayoutChanged() { frame.syncFromSettings(); }
                    }

                    x: liveX * desktop.scaleFactor
                    y: liveY * desktop.scaleFactor
                    width: liveWidth * desktop.scaleFactor
                    height: liveHeight * desktop.scaleFactor
                    z: DesktopWidgetState.editing ? 2 : 1
                    opacity: widgetEnabled ? 1 : 0
                    scale: widgetEnabled ? 1 : 0.97
                    visible: widgetEnabled || opacity > 0.001

                    Behavior on x {
                        enabled: !frame.moving && !frame.resizing
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !frame.moving && !frame.resizing
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on width {
                        enabled: !frame.resizing
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on height {
                        enabled: !frame.resizing
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Loader {
                        id: widgetLoader
                        anchors.fill: parent
                        source: ["clock", "system", "moon", "weather", "music"].indexOf(
                            frame.modelData.id) >= 0
                            ? Qt.resolvedUrl("widgets/" + frame.modelData.id + ".qml")
                            : Qt.resolvedUrl("widgets/catalog.qml")
                        active: frame.widgetEnabled
                        enabled: !DesktopWidgetState.editing
                        asynchronous: true
                        onLoaded: {
                            if (frame.modelData.id === "music")
                                desktop.musicWidget = item;
                            else if (item && ["clock", "system", "moon", "weather", "music"].indexOf(
                                frame.modelData.id) < 0)
                                item.widgetData = frame.modelData;
                        }
                        onItemChanged: {
                            if (frame.modelData.id === "music" && item === null)
                                desktop.musicWidget = null;
                            else if (item && ["clock", "system", "moon", "weather", "music"].indexOf(
                                frame.modelData.id) < 0)
                                item.widgetData = frame.modelData;
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: DesktopWidgetState.editing && frame.widgetEnabled
                        radius: 16 * desktop.scaleFactor
                        color: "transparent"
                        border.width: 2 * desktop.scaleFactor
                        border.color: Theme.primary
                    }

                    Rectangle {
                        id: resizeHandle
                        visible: DesktopWidgetState.editing && frame.widgetEnabled
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 5 * desktop.scaleFactor
                        width: 18 * desktop.scaleFactor
                        height: width
                        radius: 5 * desktop.scaleFactor
                        color: Theme.primary
                        z: 4
                    }

                }
            }

            MouseArea {
                id: widgetArrangeInput
                anchors.fill: parent
                enabled: DesktopWidgetState.editing
                visible: enabled
                z: 8
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                property var hoverFrame: null
                property bool hoverResize: false
                cursorShape: pressed
                    ? (focusScope.dragResizing ? Qt.SizeFDiagCursor : Qt.ClosedHandCursor)
                    : (hoverFrame ? (hoverResize ? Qt.SizeFDiagCursor : Qt.OpenHandCursor)
                        : Qt.ArrowCursor)

                function frameAt(x, y) {
                    for (var i = widgetRepeater.count - 1; i >= 0; i--) {
                        var candidate = widgetRepeater.itemAt(i);
                        if (candidate && candidate.widgetEnabled
                                && x >= candidate.x && x <= candidate.x + candidate.width
                                && y >= candidate.y && y <= candidate.y + candidate.height)
                            return candidate;
                    }
                    return null;
                }

                function finishDrag() {
                    if (!focusScope.draggedFrame)
                        return;
                    var target = focusScope.draggedFrame;
                    DesktopWidgetState.saveGeometry(target.modelData.id,
                        target.liveX, target.liveY, target.liveWidth, target.liveHeight);
                    target.moving = false;
                    target.resizing = false;
                    focusScope.draggedFrame = null;
                }

                onPositionChanged: function (mouse) {
                    if (!pressed) {
                        hoverFrame = frameAt(mouse.x, mouse.y);
                        hoverResize = hoverFrame
                            && mouse.x >= hoverFrame.x + hoverFrame.width - 32 * desktop.scaleFactor
                            && mouse.y >= hoverFrame.y + hoverFrame.height - 32 * desktop.scaleFactor;
                        return;
                    }
                    var target = focusScope.draggedFrame;
                    if (!target)
                        return;
                    var dx = (mouse.x - focusScope.pointerStart.x) / desktop.scaleFactor;
                    var dy = (mouse.y - focusScope.pointerStart.y) / desktop.scaleFactor;
                    if (focusScope.dragResizing) {
                        var maxWidth = desktop.width / desktop.scaleFactor - focusScope.dragXStart;
                        var maxHeight = desktop.height / desktop.scaleFactor - focusScope.dragYStart;
                        target.liveWidth = Math.max(target.modelData.minW,
                            Math.min(maxWidth, focusScope.dragWidthStart + dx));
                        target.liveHeight = Math.max(target.modelData.minH,
                            Math.min(maxHeight, focusScope.dragHeightStart + dy));
                    } else {
                        target.liveX = target.clamp(focusScope.dragXStart + dx,
                            0, desktop.width / desktop.scaleFactor - target.liveWidth);
                        target.liveY = target.clamp(focusScope.dragYStart + dy,
                            0, desktop.height / desktop.scaleFactor - target.liveHeight);
                    }
                }

                onPressed: function (mouse) {
                    var target = frameAt(mouse.x, mouse.y);
                    if (!target)
                        return;
                    focusScope.draggedFrame = target;
                    focusScope.pointerStart = Qt.point(mouse.x, mouse.y);
                    focusScope.dragXStart = target.liveX;
                    focusScope.dragYStart = target.liveY;
                    focusScope.dragWidthStart = target.liveWidth;
                    focusScope.dragHeightStart = target.liveHeight;
                    focusScope.dragResizing = mouse.x >= target.x + target.width - 32 * desktop.scaleFactor
                        && mouse.y >= target.y + target.height - 32 * desktop.scaleFactor;
                    target.moving = !focusScope.dragResizing;
                    target.resizing = focusScope.dragResizing;
                    hoverResize = focusScope.dragResizing;
                }

                onReleased: finishDrag()
                onCanceled: finishDrag()
                onExited: {
                    hoverFrame = null;
                    hoverResize = false;
                }
            }

            Rectangle {
                id: editorBar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 26 * desktop.scaleFactor
                width: editorRow.implicitWidth + 34 * desktop.scaleFactor
                height: 54 * desktop.scaleFactor
                radius: height / 2
                color: Theme.surfaceContainer
                border.width: 1
                border.color: Theme.outlineVariant
                visible: DesktopWidgetState.editing
                z: 10

                Row {
                    id: editorRow
                    anchors.centerIn: parent
                    spacing: 18 * desktop.scaleFactor

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Drag to move · corner to resize · Esc to finish"
                        color: Theme.onSurface
                        font.family: Theme.font
                        font.pixelSize: 13 * desktop.scaleFactor
                    }

                    Rectangle {
                        width: 64 * desktop.scaleFactor
                        height: 34 * desktop.scaleFactor
                        radius: height / 2
                        color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: "Done"
                            color: Theme.onPrimary
                            font.family: Theme.font
                            font.pixelSize: 12 * desktop.scaleFactor
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DesktopWidgetState.finishEditing()
                        }
                    }
                }
            }
        }
    }
}
