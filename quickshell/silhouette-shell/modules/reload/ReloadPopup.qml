import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components.icons
/**
 * Themed replacement for Quickshell's built-in reload popup. Quickshell shows
 * a system-palette popup on every hot reload; this suppresses it via
 * `Quickshell.inhibitReloadPopup()` and renders the same success/failure
 * state in the shell's own design language: a pill-like card in the top-left
 * corner, Theme tokens, the shell's glyph set, a countdown bar and
 * hover-pause so a failure can be read and copied before it fades. Success
 * flashes briefly; failures linger, offer a one-click copy of the error and
 * a copyable `qs log -i <instance>` command for the full log.
 *
 * The popup window lives in a Quickshell LazyLoader, so it is not created
 * (and not registered with the compositor) until a reload actually fires —
 * for most of the shell's lifetime it costs nothing at all. Each show tears
 * the window down and rebuilds it, so a reload landing while a popup is
 * still up replaces it cleanly.
 */
Item {
    id: root
    property bool failed: false
    property string errorString: ""
    property bool copied: false
    readonly property real s: (Quickshell.screens.length > 0 ? (Quickshell.screens[0].height / 1080) * Flags.uiScale : 1)
    /** Success flashes briefly; failures linger so the error can be read. */
    readonly property int holdMs: root.failed ? 6000 : 1600
    property bool logCopied: false
    /**
     * The command that pulls this instance's full log, surfaced on failure
     * (mirrors the built-in popup's hint). Falls back to the pid selector
     * if the instance id is unavailable.
     */
    readonly property string logCommand: {
        var id = Quickshell.instanceId;
        return id && String(id).length > 0
            ? "qs log -i " + id
            : "qs log --pid " + Quickshell.processId;
    }
    /**
     * Build the popup window and start its show animation (the window's
     * own Component.onCompleted kicks the sequence off). The loader is torn
     * down first so a reload landing while a previous popup is still up
     * rebuilds it fresh instead of being a no-op on the loaded item.
     */
    function show() {
        popupLoader.active = false;
        popupLoader.active = true;
    }
    Connections {
        target: Quickshell
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
            root.failed = false;
            root.errorString = "";
            root.show();
        }
        function onReloadFailed(error: string) {
            Quickshell.inhibitReloadPopup();
            root.failed = true;
            root.errorString = error;
            root.show();
        }
    }
    /**
     * The popup window is only built on demand. LazyLoader is a non-visual
     * component loader (not an Item), which is exactly right here: the loaded
     * root is a self-positioning layershell window that needs no visual
     * parent. `active = true` loads synchronously — the card is small and a
     * reload just rebuilt the whole config anyway, so the brief build is
     * imperceptible, and the window can appear the same frame it is shown.
     */
    LazyLoader {
        id: popupLoader

        PanelWindow {
            id: win
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:reload-popup"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Anchored to the top-left with generous breathing room from the
            // screen edges so it doesn't feel cramped against the corner.
            anchors { left: true; top: true }
            Component.onCompleted: seq.restart()
        margins { left: 36 * root.s; top: 32 * root.s }
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        Rectangle {
            id: card
            opacity: 0
            // Slight upward/leftward settle on entry, matching the top-left anchor.
            scale: 0.96
            transformOrigin: Item.TopLeft
            radius: 20 * root.s
            border.width: 1
            border.color: root.failed ? Theme.error : Theme.border
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.cardTop }
                GradientStop { position: 1.0; color: Theme.cardBot }
            }
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                shadowBlur: 0.75
                shadowVerticalOffset: 4 * root.s
            }
            // Track geometry lives here so the card's implicit height and the
            // track's own anchors agree on exactly how much room it needs —
            // this is what was causing the bar to clip past the bottom edge.
            readonly property real trackHeight: 4 * root.s
            readonly property real trackSideMargin: 34 * root.s
            readonly property real trackTopGap: 18 * root.s
            readonly property real trackBottomGap: 16 * root.s
            // More generous padding all around the content.
            implicitWidth: Math.max(column.implicitWidth, 260 * root.s) + 48 * root.s
            implicitHeight: 22 * root.s + column.implicitHeight + trackTopGap + trackHeight + trackBottomGap
            /** Hover pauses the dismiss countdown so a failure can be read. */
            HoverHandler {
                onHoveredChanged: seq.paused = hovered
            }
            /** Click anywhere dismisses early. */
            MouseArea {
                anchors.fill: parent
                onClicked: popupLoader.active = false
            }
            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 24 * root.s
                anchors.rightMargin: 24 * root.s
                anchors.topMargin: 22 * root.s
                spacing: 12 * root.s
                Row {
                    spacing: 11 * root.s
                    Rectangle {
                        width: 24 * root.s
                        height: 24 * root.s
                        radius: 7 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.failed ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.16) : Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.16)
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 13 * root.s
                            height: 13 * root.s
                            name: root.failed ? "close" : "check"
                            color: root.failed ? Theme.error : Theme.verm
                            stroke: 2.2
                        }
                    }
                    Text {
                        text: root.failed ? "Reload failed" : "Reloaded"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 14 * root.s
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Rectangle {
                    visible: root.failed
                    width: 400 * root.s
                    color: Theme.tileBg
                    radius: 12 * root.s
                    border.width: 1
                    border.color: Theme.border
                    implicitHeight: errText.implicitHeight + 18 * root.s
                    Text {
                        id: errText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12 * root.s
                        anchors.rightMargin: 12 * root.s
                        anchors.topMargin: 9 * root.s
                        text: root.errorString
                        color: Theme.cream
                        font.family: "monospace"
                        font.pixelSize: 11 * root.s
                        wrapMode: Text.Wrap
                        maximumLineCount: 6
                        elide: Text.ElideRight
                    }
                }
                Row {
                    visible: root.failed
                    spacing: 8 * root.s
                    MouseArea {
                        id: copyBtn
                        hoverEnabled: true
                        implicitWidth: copyRow.implicitWidth + 20 * root.s
                        implicitHeight: 29 * root.s
                        enabled: root.errorString.length > 0
                        onClicked: {
                            Quickshell.clipboardText = root.errorString;
                            root.copied = true;
                            copyReset.restart();
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 9 * root.s
                            color: root.copied ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.18) : (copyBtn.containsMouse ? Theme.capsule : Theme.tileBg)
                            border.width: 1
                            border.color: root.copied ? Theme.verm : (copyBtn.containsMouse ? Theme.capsuleBorder : Theme.border)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                        Row {
                            id: copyRow
                            anchors.centerIn: parent
                            spacing: 7 * root.s
                            GlyphIcon {
                                width: 13 * root.s
                                height: 13 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.copied ? "check" : "copy"
                                color: root.copied ? Theme.verm : Theme.cream
                                stroke: 2
                            }
                            Text {
                                text: root.copied ? "Copied" : "Copy error"
                                color: root.copied ? Theme.verm : Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
                /** "Run qs log -i <instance> to view the log", built-in style. */
                Row {
                    visible: root.failed
                    spacing: 7 * root.s
                    Text {
                        text: "Run"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        id: logBtn
                        hoverEnabled: true
                        implicitWidth: logText.implicitWidth + 14 * root.s
                        implicitHeight: 24 * root.s
                        onClicked: {
                            Quickshell.clipboardText = root.logCommand;
                            root.logCopied = true;
                            logCopyReset.restart();
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 6 * root.s
                            color: logBtn.containsMouse ? Theme.capsule : Theme.tileBg
                            border.width: 1
                            border.color: logBtn.containsMouse ? Theme.capsuleBorder : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                        Text {
                            id: logText
                            anchors.centerIn: parent
                            text: root.logCopied ? "Copied" : root.logCommand
                            color: root.logCopied ? Theme.cream : Theme.dim
                            font.family: "monospace"
                            font.pixelSize: 10.5 * root.s
                        }
                    }
                    Text {
                        text: "to view the log"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            /**
             * Countdown: drains as the popup's hold time elapses. Sized off
             * the same trackHeight/trackSideMargin/trackBottomGap the card
             * uses to reserve space, so it always lands centered with clean
             * margins on every side instead of poking past the card's
             * rounded corners.
             */
            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: card.trackBottomGap
                width: parent.width - (card.trackSideMargin * 2)
                height: card.trackHeight
                radius: height / 2
                color: Theme.threadBg
                clip: true
                Rectangle {
                    id: fill
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width
                    radius: height / 2
                    color: root.failed ? Theme.error : Theme.verm
                    // Faint glow riding the leading edge of the fill for a
                    // little more polish than a flat bar.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 10 * root.s
                        radius: height / 2
                        visible: fill.width > width
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.35) }
                        }
                    }
                }
            }
        }
        SequentialAnimation {
            id: seq
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { target: card; property: "scale"; from: 0.96; to: 1; duration: 220; easing.type: Easing.OutBack }
            }
            ParallelAnimation {
                PauseAnimation { duration: root.holdMs }
                NumberAnimation {
                    target: fill
                    property: "width"
                    from: track.width
                    to: 0
                    duration: root.holdMs
                    easing.type: Easing.Linear
                }
            }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InQuad }
            onFinished: popupLoader.active = false
        }
        Timer {
            id: copyReset
            interval: 1200
            onTriggered: root.copied = false
        }
        Timer {
            id: logCopyReset
            interval: 1200
            onTriggered: root.logCopied = false
        }
    }
    }
}
