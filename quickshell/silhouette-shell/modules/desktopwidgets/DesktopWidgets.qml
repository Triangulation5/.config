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
        readonly property real inputWidth: {
            var edge = 0;
            var items = DesktopWidgetState.enabledWidgets;
            for (var i = 0; i < items.length; i++)
                edge = Math.max(edge, (items[i].x + items[i].w) * scaleFactor);
            return edge;
        }
        readonly property real inputHeight: {
            var edge = 0;
            var items = DesktopWidgetState.enabledWidgets;
            for (var i = 0; i < items.length; i++)
                edge = Math.max(edge, (items[i].y + items[i].h) * scaleFactor);
            return edge;
        }

        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "silhouette-desktop-widgets"
        WlrLayershell.layer: DesktopWidgetState.editing ? WlrLayer.Overlay : WlrLayer.Bottom
        WlrLayershell.keyboardFocus: DesktopWidgetState.editing
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        mask: DesktopWidgetState.editing ? fullRegion : widgetsRegion

        Region {
            id: widgetsRegion
            width: desktop.inputWidth
            height: desktop.inputHeight
        }
        Region {
            id: fullRegion
            width: desktop.width
            height: desktop.height
        }

        Component.onCompleted: {
            Sysmon.desktopOpen = DesktopWidgetState.isEnabled("system");
            if (DesktopWidgetState.isEnabled("moon") || DesktopWidgetState.isEnabled("weather"))
                Weather.needed = true;
        }
        Component.onDestruction: Sysmon.desktopOpen = false

        Connections {
            target: DesktopWidgetState
            function onLayoutChanged() {
                Sysmon.desktopOpen = DesktopWidgetState.isEnabled("system");
                if (DesktopWidgetState.isEnabled("moon") || DesktopWidgetState.isEnabled("weather"))
                    Weather.needed = true;
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

            Repeater {
                id: widgetRepeater
                model: DesktopWidgetState.catalog

                delegate: Item {
                    id: frame

                    required property var modelData

                    readonly property var settings: DesktopWidgetState.widget(frame.modelData.id)
                    readonly property bool widgetEnabled: settings ? settings.enabled : false
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
                        if (!frame.settings)
                            return;
                        frame.liveX = frame.settings.x;
                        frame.liveY = frame.settings.y;
                        frame.liveWidth = frame.settings.w;
                        frame.liveHeight = frame.settings.h;
                    }
                    onSettingsChanged: frame.syncFromSettings()

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
                        anchors.fill: parent
                        source: Qt.resolvedUrl("widgets/" + frame.modelData.id + ".qml")
                        active: frame.visible
                        asynchronous: true
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
                id: editorInput
                anchors.fill: parent
                enabled: DesktopWidgetState.editing
                z: 5
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                property var dragFrame: null
                property bool resizing: false
                property point pointerStart
                property real xStart: 0
                property real yStart: 0
                property real widthStart: 0
                property real heightStart: 0
                cursorShape: resizing ? Qt.SizeFDiagCursor
                    : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

                onPressed: function (mouse) {
                    dragFrame = null;
                    for (var i = widgetRepeater.count - 1; i >= 0; i--) {
                        var candidate = widgetRepeater.itemAt(i);
                        if (!candidate || !candidate.widgetEnabled)
                            continue;
                        var local = focusScope.mapToItem(candidate, mouse.x, mouse.y);
                        if (local.x < 0 || local.y < 0
                                || local.x > candidate.width || local.y > candidate.height)
                            continue;
                        dragFrame = candidate;
                        resizing = local.x >= candidate.width - 28 * desktop.scaleFactor
                            && local.y >= candidate.height - 28 * desktop.scaleFactor;
                        pointerStart = Qt.point(mouse.x, mouse.y);
                        xStart = candidate.liveX;
                        yStart = candidate.liveY;
                        widthStart = candidate.liveWidth;
                        heightStart = candidate.liveHeight;
                        candidate.moving = !resizing;
                        candidate.resizing = resizing;
                        break;
                    }
                    if (!dragFrame)
                        mouse.accepted = false;
                }

                onPositionChanged: function (mouse) {
                    if (!pressed || !dragFrame)
                        return;
                    var dx = (mouse.x - pointerStart.x) / desktop.scaleFactor;
                    var dy = (mouse.y - pointerStart.y) / desktop.scaleFactor;
                    if (resizing) {
                        dragFrame.liveWidth = dragFrame.clamp(widthStart + dx,
                            dragFrame.modelData.minW, dragFrame.modelData.maxW);
                        dragFrame.liveHeight = dragFrame.clamp(heightStart + dy,
                            dragFrame.modelData.minH, dragFrame.modelData.maxH);
                        dragFrame.liveWidth = Math.min(dragFrame.liveWidth,
                            desktop.width / desktop.scaleFactor - dragFrame.liveX);
                        dragFrame.liveHeight = Math.min(dragFrame.liveHeight,
                            desktop.height / desktop.scaleFactor - dragFrame.liveY);
                    } else {
                        dragFrame.liveX = dragFrame.clamp(xStart + dx,
                            0, desktop.width / desktop.scaleFactor - dragFrame.liveWidth);
                        dragFrame.liveY = dragFrame.clamp(yStart + dy,
                            0, desktop.height / desktop.scaleFactor - dragFrame.liveHeight);
                    }
                }

                function finishDrag() {
                    if (!dragFrame)
                        return;
                    dragFrame.saveGeometry();
                    dragFrame.moving = false;
                    dragFrame.resizing = false;
                    dragFrame.syncFromSettings();
                    dragFrame = null;
                    resizing = false;
                }

                onReleased: finishDrag()
                onCanceled: finishDrag()
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
