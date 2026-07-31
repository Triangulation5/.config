pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import "Singletons"

Item {
    id: content
    property real s: 1.1
    property var auth: null
    property bool isMain: true

    property bool clockExpanded: false
    property bool revealPassword: false

    readonly property bool authenticating: auth ? auth.authenticating : false
    property bool showError: false
    property bool showCursor: false

    Shortcut {
        sequence: "Escape"

        onActivated: {
            content.clockExpanded = false;
        }
    }

    Connections {
        target: content.auth
        enabled: content.auth !== null
        function onFailed() {
            content.showError = true;
            input.text = "";
            shake.restart();
        }
        function onSucceeded() {
            content.showError = false;
            input.text = "";
        }
    }

    readonly property var player: {
        var list = Mpris.players.values;
        if (!list || list.length === 0)
            return null;
        var controllable = null;
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (!p)
                continue;
            if (p.isPlaying)
                return p;
            if (!controllable && p.canControl)
                controllable = p;
        }
        return controllable ? controllable : list[0];
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer && player.isPlaying

    readonly property string trackTitle: {
        if (!player)
            return "";
        return player.trackTitle ? player.trackTitle : "";
    }
    readonly property string trackArtist: {
        if (!player)
            return "";
        if (player.trackArtists && player.trackArtists.length > 0)
            return player.trackArtists;
        return player.trackArtist ? player.trackArtist : "";
    }
    readonly property string artUrl: {
        if (!player)
            return "";
        return player.trackArtUrl ? player.trackArtUrl : "";
    }
    readonly property real lengthSec: hasPlayer && player.length > 0 ? player.length : 0
    readonly property real positionSec: hasPlayer ? player.position : 0
    readonly property real progress: lengthSec > 0 ? Math.max(0, Math.min(1, positionSec / lengthSec)) : 0

    function fmtTime(sec) {
        var m = Math.floor(sec / 60);
        var ss = Math.floor(sec % 60);
        return m + ":" + (ss < 10 ? "0" : "") + ss;
    }

    readonly property string metaLine: {
        var t = lengthSec > 0 ? fmtTime(positionSec) + " / " + fmtTime(lengthSec) : "";
        if (trackArtist.length > 0 && t.length > 0)
            return trackArtist + " · " + t;
        return trackArtist.length > 0 ? trackArtist : t;
    }

    Timer {
        interval: 1000
        running: content.playing && content.isMain
        repeat: true
        onTriggered: if (content.player) content.player.positionChanged()
    }

    BatterySurface {
        id: batteryIndicator

        z: 10

        visible: content.isMain && !content.clockExpanded

        anchors.right: parent.right
        anchors.top: parent.top

        anchors.rightMargin: parent.width * 0.055
        anchors.topMargin: parent.height * 0.065

        s: content.s
    }

    Clock {
        id: mainClock

        anchors.fill: parent

        s: content.s
        visibleClock: content.isMain

        expanded: content.clockExpanded

        onClockClicked: {
            content.clockExpanded = !content.clockExpanded;
        }
    }

    Column {
        visible: content.isMain && content.hasPlayer && !content.clockExpanded
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: parent.width * 0.045
        anchors.bottomMargin: parent.height * 0.075
        spacing: 9 * content.s

        Row {
            spacing: 12 * content.s

            Rectangle {
                width: 53 * content.s
                height: 53 * content.s
                radius: 11 * content.s
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: "#1a100c"
                Image {
                    id: coverImg
                    anchors.fill: parent
                    visible: content.artUrl.length > 0
                    source: content.artUrl
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    cache: false
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: coverMask
                    }
                }
                Item {
                    id: coverMask
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Rectangle {
                        anchors.fill: parent
                        radius: 10 * content.s
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * content.s

                Text {
                    text: content.trackTitle.length > 0 ? content.trackTitle : "Unknown"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 12 * content.s
                    font.weight: 600
                    elide: Text.ElideRight
                    width: 154 * content.s
                }
                Text {
                    visible: content.metaLine.length > 0
                    text: content.metaLine
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * content.s
                    font.weight: 500
                    elide: Text.ElideRight
                    width: 154 * content.s
                }
            }
        }

        Item {
            width: 220 * content.s
            height: 2.2

            Rectangle {
                anchors.fill: parent
                radius: 1
                color: Theme.trackBg
            }
            Rectangle {
                id: threadFill
                width: parent.width * content.progress
                height: parent.height
                radius: 1
                color: Theme.verm
            }
            Rectangle {
                x: Math.min(parent.width - width, Math.max(0, threadFill.width - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 8 * content.s
                height: 8 * content.s
                radius: width / 2
                color: Theme.cream
            }
        }
    }

    Rectangle {
        id: capsule
        visible: !content.clockExpanded
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.09
        width: 340 * content.s
        height: 50 * content.s
        radius: height / 2
        color: Theme.capsule
        border.width: 1
        border.color: Theme.capsuleBorder
        opacity: content.isMain ? (content.authenticating ? 0.6 : 1) : 0

        transform: Translate { id: capsuleShift }

        SequentialAnimation {
            id: shake
            NumberAnimation { target: capsuleShift; property: "x"; to: 9 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: -9 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: 6 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: -6 * content.s; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: 0; duration: 50 }
        }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 24 * content.s
            anchors.rightMargin: 24 * content.s
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter

            echoMode: revealPassword ? TextInput.Normal : TextInput.NoEcho
            color: revealPassword ? Theme.bright : "transparent"

            font.family: Theme.font
            font.pixelSize: 15 * content.s
            font.letterSpacing: 2 * content.s
            clip: true
            focus: content.isMain && !content.clockExpanded
            enabled: !content.authenticating

            onTextChanged: {
                if (text.length > 0)
                    content.showError = false;
                if (Pw.text !== text)
                    Pw.text = text;
            }

            Connections {
                target: Pw
                function onTextChanged() {
                    if (input.text !== Pw.text)
                        input.text = Pw.text;
                }
            }

            onAccepted: {
                if (content.auth && text.length > 0)
                    content.auth.submit(text);
            }

            cursorDelegate: Rectangle {
                visible: content.showCursor && input.activeFocus
                width: 2 * content.s
                height: input.cursorRectangle.height
                color: Theme.verm

                SequentialAnimation on opacity {
                    running: content.showCursor && input.activeFocus
                    loops: Animation.Infinite

                    NumberAnimation { to: 0; duration: 0 }
                    PauseAnimation { duration: 550 }
                    NumberAnimation { to: 1; duration: 0 }
                    PauseAnimation { duration: 550 }
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 7 * content.s
                visible: input.text.length > 0 && !content.revealPassword

                ListModel {
                    id: passwordDots
                }

                Connections {
                    target: input

                    property int previousLength: 0

                    function onTextChanged() {
                        var current = input.text.length;

                        if (current > previousLength) {
                            for (var i = previousLength; i < current; ++i)
                                passwordDots.append({});
                        } else if (current < previousLength) {
                            for (var j = previousLength; j > current; --j)
                                passwordDots.remove(passwordDots.count - 1);
                        }

                        previousLength = current;
                    }
                }

                Repeater {
                    model: passwordDots

                    Rectangle {
                        id: dot

                        width: 9 * content.s
                        height: width
                        radius: width / 2
                        color: Theme.bright

                        antialiasing: true
                        smooth: true

                        property real lift: -4 * content.s
                        property real dotScale: 0.72
                        property real dotOpacity: 0
                        property real slideX: 0

                        opacity: dotOpacity
                        scale: dotScale

                        transform: Translate {
                            x: dot.slideX
                            y: dot.lift
                        }

                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowBlur: 0.55
                            shadowVerticalOffset: 1
                            shadowHorizontalOffset: 0
                            shadowColor: Qt.rgba(0, 0, 0, 0.16)
                        }

                        Behavior on lift {
                            SpringAnimation {
                                spring: 4.8
                                damping: 0.34
                            }
                        }

                        Behavior on dotScale {
                            SpringAnimation {
                                spring: 5.5
                                damping: 0.36
                            }
                        }

                        Behavior on dotOpacity {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.OutQuad
                            }
                        }


                        Behavior on slideX {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }

                        Component.onCompleted: {
                            dotOpacity = 1;
                            dotScale = 1;
                            lift = 0;

                            if (index === passwordDots.count - 1) {
                                slideX = 8 * content.s;

                                Qt.callLater(function() {
                                    slideX = 0;
                                });
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: input.text.length === 0

                text: {
                    if (!content.showError)
                        return "<i>enter password</i>"
                    var pamMsg = content.auth ? content.auth.lastError : "";
                    return pamMsg.length > 0 ? pamMsg.toLowerCase() : "wrong password";
                }

                textFormat: Text.RichText
                color: content.showError ? Theme.error : Theme.placeholder
                font.family: Theme.font
                font.pixelSize: 14 * content.s
                font.letterSpacing: 1 * content.s
            }
        }

        GlyphIcon {
            anchors.right: parent.right
            anchors.rightMargin: 16 * content.s
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * content.s
            height: 20 * content.s
            name: content.revealPassword ? "eye-off" : "eye"
            color: Theme.placeholder
            stroke: 1.8

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8 * content.s
                onClicked: content.revealPassword ^= true
            }
        }
    }
}
