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
                model: DesktopWidgetState.enabledWidgets

                delegate: Item {
                    id: frame

                    required property var modelData

                    property real liveX: modelData.x
                    property real liveY: modelData.y
                    property real liveWidth: modelData.w
                    property real liveHeight: modelData.h
                    property bool moving: false
                    property bool resizing: false
                    property point pointerStart
                    property real geometryXStart: 0
                    property real geometryYStart: 0
                    property real geometryWidthStart: 0
                    property real geometryHeightStart: 0

                    function clamp(value, lower, upper) {
                        return Math.max(lower, Math.min(upper, value));
                    }

                    onModelDataChanged: {
                        if (frame.moving || frame.resizing)
                            return;
                        frame.liveX = modelData.x;
                        frame.liveY = modelData.y;
                        frame.liveWidth = modelData.w;
                        frame.liveHeight = modelData.h;
                    }

                    x: liveX * desktop.scaleFactor
                    y: liveY * desktop.scaleFactor
                    width: liveWidth * desktop.scaleFactor
                    height: liveHeight * desktop.scaleFactor
                    z: DesktopWidgetState.editing ? 2 : 1

                    Loader {
                        anchors.fill: parent
                        source: Qt.resolvedUrl("widgets/" + frame.modelData.id + ".qml")
                        asynchronous: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: DesktopWidgetState.editing
                        radius: 16 * desktop.scaleFactor
                        color: "transparent"
                        border.width: 2 * desktop.scaleFactor
                        border.color: Theme.primary
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        enabled: DesktopWidgetState.editing
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        onPressed: function (mouse) {
                            frame.moving = true;
                            frame.pointerStart = mapToItem(focusScope, mouse.x, mouse.y);
                            frame.geometryXStart = frame.liveX;
                            frame.geometryYStart = frame.liveY;
                        }
                        onPositionChanged: function (mouse) {
                            if (!pressed)
                                return;
                            var point = mapToItem(focusScope, mouse.x, mouse.y);
                            frame.liveX = frame.clamp(frame.geometryXStart
                                + (point.x - frame.pointerStart.x) / desktop.scaleFactor,
                                0, desktop.width / desktop.scaleFactor - frame.liveWidth);
                            frame.liveY = frame.clamp(frame.geometryYStart
                                + (point.y - frame.pointerStart.y) / desktop.scaleFactor,
                                0, desktop.height / desktop.scaleFactor - frame.liveHeight);
                        }
                        onReleased: {
                            frame.moving = false;
                            DesktopWidgetState.saveGeometry(frame.modelData.id,
                                frame.liveX, frame.liveY, frame.liveWidth, frame.liveHeight);
                        }
                    }

                    Rectangle {
                        id: resizeHandle
                        visible: DesktopWidgetState.editing
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 5 * desktop.scaleFactor
                        width: 18 * desktop.scaleFactor
                        height: width
                        radius: 5 * desktop.scaleFactor
                        color: Theme.primary
                        z: 4

                        MouseArea {
                            anchors.fill: parent
                            enabled: DesktopWidgetState.editing
                            preventStealing: true
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                frame.resizing = true;
                                frame.pointerStart = mapToItem(focusScope, mouse.x, mouse.y);
                                frame.geometryWidthStart = frame.liveWidth;
                                frame.geometryHeightStart = frame.liveHeight;
                            }
                            onPositionChanged: function (mouse) {
                                if (!pressed)
                                    return;
                                var point = mapToItem(focusScope, mouse.x, mouse.y);
                                frame.liveWidth = frame.clamp(frame.geometryWidthStart
                                    + (point.x - frame.pointerStart.x) / desktop.scaleFactor,
                                    frame.modelData.minW, frame.modelData.maxW);
                                frame.liveHeight = frame.clamp(frame.geometryHeightStart
                                    + (point.y - frame.pointerStart.y) / desktop.scaleFactor,
                                    frame.modelData.minH, frame.modelData.maxH);
                                frame.liveWidth = Math.min(frame.liveWidth,
                                    desktop.width / desktop.scaleFactor - frame.liveX);
                                frame.liveHeight = Math.min(frame.liveHeight,
                                    desktop.height / desktop.scaleFactor - frame.liveY);
                            }
                            onReleased: {
                                frame.resizing = false;
                                DesktopWidgetState.saveGeometry(frame.modelData.id,
                                    frame.liveX, frame.liveY, frame.liveWidth, frame.liveHeight);
                            }
                        }
                    }
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
