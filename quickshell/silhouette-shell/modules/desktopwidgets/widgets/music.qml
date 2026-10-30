import QtQuick
import QtQuick.Shapes
import qs.services
import qs.components.icons
import qs.components.controls
import qs.modules.desktopwidgets

Item {
    id: root

    readonly property real s: Math.max(0.78, Math.min(1.7, Math.min(width / 535, height / 122)))
    readonly property real stubWidth: Math.min(142 * s, Math.max(108 * s, width * 0.27))
    readonly property real perforationX: width - stubWidth
    readonly property real radius: Math.min(22 * s, height * 0.25)
    readonly property var player: Players.active
    readonly property bool hasPlayer: player !== null && player !== undefined
    readonly property real length: Players.lengthSec
    readonly property real position: hasPlayer ? Math.max(0, player.position) : 0
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    readonly property string title: Players.has && Players.title.length > 0 ? Players.title : "Nothing playing"
    readonly property string artist: Players.has ? Players.artist : "Start a track to see it here"
    readonly property string album: hasPlayer && player.trackAlbum ? player.trackAlbum : "\u2014"
    readonly property string source: Players.serviceLabel.length > 0 ? Players.serviceLabel : "\u2014"
    readonly property bool ticketMode: DesktopWidgetState.musicStyle === "ticket"
    readonly property bool ticketTransportEnabled: hasPlayer && player.canTogglePlaying
    readonly property bool lineTransportEnabled: hasPlayer && player.canTogglePlaying
    readonly property bool ticketSeekEnabled: hasPlayer && player.canSeek
        && player.positionSupported && length > 0 && !Players.live
    readonly property bool lineSeekEnabled: hasPlayer && player.canSeek
        && player.positionSupported && length > 0 && !Players.live
    readonly property alias ticketSeekInput: ticketSeekMouseArea
    readonly property alias ticketTransportInput: ticketTransportRow
    readonly property alias lineSeekInput: lineSeekMouseArea
    readonly property alias lineTransportInput: lineTransportRow

    function formatTime(seconds) {
        var value = Math.max(0, Math.floor(seconds || 0));
        var minutes = Math.floor(value / 60);
        var rest = value % 60;
        return minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }

    Timer {
        interval: 500
        repeat: true
        running: root.hasPlayer && root.player.positionSupported
        onTriggered: if (root.hasPlayer) root.player.positionChanged()
    }

    Shape {
        visible: root.ticketMode
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Theme.surfaceContainerLowest
            strokeColor: Qt.alpha(Theme.outlineVariant, 0.35)
            strokeWidth: 1
            startX: root.radius
            startY: 0
            PathLine { x: root.perforationX - 11 * root.s; y: 0 }
            PathArc {
                x: root.perforationX + 11 * root.s
                y: 0
                radiusX: 11 * root.s
                radiusY: 11 * root.s
                direction: PathArc.Counterclockwise
            }
            PathLine { x: root.width - root.radius; y: 0 }
            PathArc { x: root.width; y: root.radius; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: root.width; y: root.height - root.radius }
            PathArc { x: root.width - root.radius; y: root.height; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: root.perforationX + 11 * root.s; y: root.height }
            PathArc {
                x: root.perforationX - 11 * root.s
                y: root.height
                radiusX: 11 * root.s
                radiusY: 11 * root.s
                direction: PathArc.Counterclockwise
            }
            PathLine { x: root.radius; y: root.height }
            PathArc { x: 0; y: root.height - root.radius; radiusX: root.radius; radiusY: root.radius }
            PathLine { x: 0; y: root.radius }
            PathArc { x: root.radius; y: 0; radiusX: root.radius; radiusY: root.radius }
        }

        ShapePath {
            strokeColor: Qt.alpha(Theme.onSurfaceVariant, 0.55)
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 2]
            fillColor: "transparent"
            startX: root.perforationX
            startY: 14 * root.s
            PathLine { x: root.perforationX; y: root.height - 14 * root.s }
        }
    }

    Item {
        visible: root.ticketMode
        x: 16 * root.s
        y: 14 * root.s
        width: root.perforationX - 34 * root.s
        height: parent.height - 24 * root.s

        Text {
            id: status
            text: Players.has ? "ADMIT ONE \u00B7 " + (Players.playing ? "NOW PLAYING" : "PAUSED") : "ADMIT ONE \u00B7 MUSIC"
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 1.4 * root.s
        }

        Text {
            id: titleText
            y: 17 * root.s
            width: parent.width
            text: root.title
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 20 * root.s
            font.weight: Font.Bold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            anchors.top: titleText.bottom
            anchors.topMargin: 1 * root.s
            width: parent.width
            text: root.artist
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 16 * root.s

            Column {
                width: parent.width * 0.45
                spacing: 1
                Text {
                    text: "ALBUM"
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2 * root.s
                }
                Text {
                    width: parent.width
                    text: root.album
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    elide: Text.ElideRight
                }
            }

            Column {
                width: parent.width * 0.3
                spacing: 1
                Text {
                    text: "PLAYER"
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2 * root.s
                }
                Text {
                    width: parent.width
                    text: root.source
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    elide: Text.ElideRight
                }
            }

            Column {
                width: parent.width * 0.2
                spacing: 1
                Text {
                    text: "LENGTH"
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2 * root.s
                }
                Text {
                    width: parent.width
                    text: Players.has && !Players.live ? root.formatTime(root.length) : "\u2014"
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                }
            }
        }
    }

    Column {
        visible: root.ticketMode
        x: root.perforationX + 12 * root.s
        y: 8 * root.s
        width: root.stubWidth - 24 * root.s
        spacing: 3 * root.s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "TIME"
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 8 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 1.3 * root.s
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Players.has ? root.formatTime(root.position) : "0:00"
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 19 * root.s
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }

        Item {
            id: barcode
            width: parent.width
            height: 22 * root.s
            anchors.horizontalCenter: parent.horizontalCenter

            Row {
                anchors.fill: parent
                spacing: 1.5 * root.s

                Repeater {
                    model: [3, 5, 2, 2, 4, 2, 3, 5, 2, 4, 2, 3, 2, 5, 3, 2, 4, 2, 3, 5, 2, 2, 4, 3]

                    delegate: Rectangle {
                        required property int modelData
                        required property int index
                        width: modelData * 0.62 * root.s
                        height: barcode.height
                        color: index / 24 < root.progress
                            ? Theme.onSurface : Qt.alpha(Theme.onSurface, 0.28)
                    }
                }
            }

            MouseArea {
                id: ticketSeekMouseArea
                anchors.fill: parent
                enabled: root.hasPlayer && player.canSeek && player.positionSupported
                    && root.length > 0 && !Players.live
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function (mouse) {
                    if (!root.hasPlayer)
                        return;
                    var target = Math.max(0, Math.min(1, mouse.x / width)) * root.length;
                    player.position = target;
                    player.positionChanged();
                }
            }
        }

        Row {
            id: ticketTransportRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2 * root.s

            TransportButton {
                icon: "prev"
                enabled: root.hasPlayer && player.canGoPrevious
                onActivated: if (root.hasPlayer) player.previous()
            }
            TransportButton {
                icon: Players.playing ? "pause" : "play"
                highlighted: true
                enabled: root.hasPlayer && player.canTogglePlaying
                onActivated: if (root.hasPlayer) player.togglePlaying()
            }
            TransportButton {
                icon: "next"
                enabled: root.hasPlayer && player.canGoNext
                onActivated: if (root.hasPlayer) player.next()
            }
        }
    }

    Item {
        id: lineStyle
        anchors.fill: parent
        visible: !root.ticketMode

        Rectangle {
            anchors.fill: parent
            radius: 24 * root.s
            color: Theme.surfaceContainerLowest
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.32)
        }

        Text {
            x: 16 * root.s
            y: 14 * root.s
            text: "NOW PLAYING"
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 1.2 * root.s
        }

        Text {
            id: lineTitle
            x: 16 * root.s
            y: 29 * root.s
            width: parent.width - 156 * root.s
            text: root.title
            color: Theme.onSurface
            font.family: Theme.font
            font.pixelSize: 17 * root.s
            font.weight: Font.Bold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            anchors.left: lineTitle.left
            anchors.top: lineTitle.bottom
            anchors.topMargin: 2 * root.s
            width: lineTitle.width
            text: root.artist
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Row {
            id: lineTransportRow
            anchors.right: parent.right
            anchors.rightMargin: 16 * root.s
            anchors.top: parent.top
            anchors.topMargin: 27 * root.s
            spacing: 5 * root.s

            TransportButton {
                icon: "prev"
                enabled: root.hasPlayer && player.canGoPrevious
                onActivated: if (root.hasPlayer) player.previous()
            }
            TransportButton {
                icon: Players.playing ? "pause" : "play"
                highlighted: true
                enabled: root.hasPlayer && player.canTogglePlaying
                onActivated: if (root.hasPlayer) player.togglePlaying()
            }
            TransportButton {
                icon: "next"
                enabled: root.hasPlayer && player.canGoNext
                onActivated: if (root.hasPlayer) player.next()
            }
        }

        WaveProgress {
            id: waveform
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16 * root.s
            anchors.rightMargin: 16 * root.s
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12 * root.s
            height: 20 * root.s
            value: root.progress
            actualValue: root.progress
            isPlaying: Players.playing
            lineWidth: 2 * root.s
            amplitude: 1.6 * root.s
            wavelength: 20 * root.s
            trackColor: Qt.alpha(Theme.onSurfaceVariant, 0.35)
            fillColor: Theme.primary
            playheadColor: Theme.onSurface
            actualProgressColor: Theme.onSurfaceVariant

            MouseArea {
                id: lineSeekMouseArea
                anchors.fill: parent
                enabled: root.hasPlayer && player.canSeek && player.positionSupported
                    && root.length > 0 && !Players.live
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function (mouse) {
                    if (!root.hasPlayer)
                        return;
                    player.position = Math.max(0, Math.min(1, mouse.x / width)) * root.length;
                    player.positionChanged();
                }
            }
        }
    }

    component TransportButton: Item {
        id: button

        property string icon: ""
        property bool highlighted: false
        signal activated()

        width: 25 * root.s
        height: 25 * root.s
        opacity: enabled ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: button.highlighted ? Theme.onSurface : "transparent"
        }

        GlyphIcon {
            anchors.centerIn: parent
            width: 13 * root.s
            height: width
            name: button.icon
            color: button.highlighted ? Theme.surfaceContainerLowest : Theme.onSurface
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.activated()
        }
    }
}
