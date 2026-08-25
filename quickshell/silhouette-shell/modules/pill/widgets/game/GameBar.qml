pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.icons

/**
 * Game-mode face: the pill docks into a flush top bar carrying only the clock
 * and, when something plays, the current track. Everything else the desktop
 * usually shows is deliberately gone. Pure face - geometry, media and OSD state
 * are fed in from the pill, so it can never drift from the pill's own mode.
 */
Item {
    id: root

    property real s: 1.1

    /** True while game mode owns the pill. */
    property bool active: false

    /** How settled the pill is into its target geometry; drives the fade-in. */
    property real morph: 0

    /** The clock text, fed by the pill's clock object. */
    property string time: ""

    /** The pill's OSD, so volume/brightness feedback can ride the bar. */
    property var osd: null

    /** True while the OSD is flashing the inline volume/brightness level chip. */
    readonly property bool levelFlash: root.osd.flashing
        && (root.osd.kind === "volume" || root.osd.kind === "brightness")
    /** The level the chip renders: brightness when that kind is flashing, else volume. */
    readonly property real levelValue: root.osd.kind === "brightness" ? root.osd.brightness : root.osd.volume
    /** True while the chip shows the muted state (volume flash on a muted sink). */
    readonly property bool levelMuted: root.osd.kind === "volume" && root.osd.muted

    enabled: root.active
    opacity: root.active ? Math.pow(root.morph, 1.2) : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 18 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9 * root.s
        opacity: Players.playing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 26 * root.s
            height: 26 * root.s
            radius: 7 * root.s
            color: Theme.tileBg
            clip: true
            Image {
                anchors.fill: parent
                source: Players.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: Players.title
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * root.s
                font.weight: Font.Medium
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 220 * root.s)
            }
            Text {
                text: Players.artist
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 220 * root.s)
                visible: text.length > 0
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.time
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 16 * root.s
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
    }

    /**
     * Volume/brightness feedback stays visible while gaming as a compact
     * chip on the bar's right, since the full OSD face is parked behind
     * game mode in the mode ladder. Notifications stay suppressed.
     */
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 18 * root.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9 * root.s
        opacity: root.levelFlash ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.fast }
        }

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 14 * root.s
            height: 14 * root.s
            name: root.osd.kind === "brightness" ? "sun" : (root.levelMuted ? "speaker-off" : "speaker")
            color: root.levelMuted ? Theme.dim : Theme.iconDim
            stroke: 1.7
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 64 * root.s
            height: 3 * root.s
            radius: 1.5 * root.s
            color: Theme.threadBg

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.levelValue
                radius: parent.radius
                color: root.levelMuted ? Theme.vermDim : Theme.vermLit
                Behavior on width { NumberAnimation { duration: Motion.fast } }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.levelValue * 100) + "%"
            color: root.levelMuted ? Theme.dim : Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }
}
