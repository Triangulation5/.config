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
                    && DesktopWidgetState.musicStyle === "line"
                    && desktop.musicWidget.lineSeekEnabled
                    ? desktop.musicWidget.lineSeekInput : null
                intersection: Intersection.Combine
            }
            Region {
                item: desktop.musicWidget
                    && DesktopWidgetState.musicStyle === "line"
                    && desktop.musicWidget.lineTransportEnabled
                    ? desktop.musicWidget.lineTransportInput : null
                intersection: Intersection.Combine
            }
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
                        id: widgetLoader
                        anchors.fill: parent
                        source: Qt.resolvedUrl("widgets/" + frame.modelData.id + ".qml")
                        active: frame.widgetEnabled || DesktopWidgetState.editing
                        enabled: !DesktopWidgetState.editing
                        asynchronous: true
                        onLoaded: if (frame.modelData.id === "music") desktop.musicWidget = item
                        onItemChanged: if (frame.modelData.id === "music" && item === null)
                            desktop.musicWidget = null
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

                    DragHandler {
                        id: widgetEditorInput
                        enabled: DesktopWidgetState.editing && frame.widgetEnabled
                        acceptedButtons: Qt.LeftButton
                        acceptedDevices: PointerDevice.Mouse
                        target: null
                        property bool resizing: false
                        property real xStart: 0
                        property real yStart: 0
                        property real widthStart: 0
                        property real heightStart: 0
                        cursorShape: resizing ? Qt.SizeFDiagCursor
                            : (active ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

                        onActiveChanged: {
                            if (active) {
                                xStart = frame.liveX;
                                yStart = frame.liveY;
                                widthStart = frame.liveWidth;
                                heightStart = frame.liveHeight;
                                resizing = centroid.pressPosition.x >= frame.width - 32 * desktop.scaleFactor
                                    && centroid.pressPosition.y >= frame.height - 32 * desktop.scaleFactor;
                                frame.moving = !resizing;
                                frame.resizing = resizing;
                            } else {
                                DesktopWidgetState.saveGeometry(frame.modelData.id,
                                    frame.liveX, frame.liveY, frame.liveWidth, frame.liveHeight);
                                frame.moving = false;
                                frame.resizing = false;
                            }
                        }

                        onTranslationChanged: {
                            if (!active)
                                return;
                            var dx = translation.x / desktop.scaleFactor;
                            var dy = translation.y / desktop.scaleFactor;
                            if (resizing) {
                                var maxWidth = desktop.width / desktop.scaleFactor - xStart;
                                var maxHeight = desktop.height / desktop.scaleFactor - yStart;
                                frame.liveWidth = Math.max(frame.modelData.minW,
                                    Math.min(maxWidth, widthStart + dx));
                                frame.liveHeight = Math.max(frame.modelData.minH,
                                    Math.min(maxHeight, heightStart + dy));
                            } else {
                                frame.liveX = frame.clamp(xStart + dx,
                                    0, desktop.width / desktop.scaleFactor - frame.liveWidth);
                                frame.liveY = frame.clamp(yStart + dy,
                                    0, desktop.height / desktop.scaleFactor - frame.liveHeight);
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
