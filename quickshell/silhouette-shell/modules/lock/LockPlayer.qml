pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * Lock screen now-playing block: album art, track and meta text, and the
 * progress thread with its knob. Visible only while a player is active and the
 * clock is collapsed; all state comes from the lock surface (`host`).
 */
Column {
    id: root

    property real s: 1.1
    property var host: null

    /**
     * Redaction gate (Flags.lockPrivacy): while it is on nothing that identifies
     * the track is drawn — no cover, no title, no artist or position text. The
     * card and its progress thread stay, so the lock still says something is
     * playing without saying what.
     */
    readonly property bool redacted: Flags.lockPrivacy

    visible: Flags.lockMedia && host.hasPlayer && !host.clockExpanded
    opacity: host.clockExpanded ? 0 : 1
    Behavior on opacity {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
    spacing: 9 * root.s

    Row {
        spacing: 12 * root.s

        Rectangle {
            width: 53 * root.s
            height: 53 * root.s
            radius: 16 * root.s
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: "#1a100c"
            Image {
                id: coverImg
                anchors.fill: parent
                visible: host.artUrl.length > 0 && !root.redacted
                source: host.artUrl
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
                    radius: 16 * root.s
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * root.s

            Text {
                text: root.redacted
                    ? "Media hidden"
                    : (host.trackTitle.length > 0 ? host.trackTitle : "Unknown")
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 12 * root.s
                font.weight: 600
                elide: Text.ElideRight
                width: 154 * root.s
            }
            Text {
                visible: host.metaLine.length > 0 && !root.redacted
                text: host.metaLine
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: 500
                elide: Text.ElideRight
                width: 154 * root.s
            }
        }
    }

    Item {
        width: 220 * root.s
        height: 2.2

        Rectangle {
            anchors.fill: parent
            radius: 1
            color: Theme.trackBg
        }
        Rectangle {
            id: threadFill
            width: parent.width * host.progress
            height: parent.height
            radius: 1
            color: Theme.verm
        }
        Rectangle {
            x: Math.min(parent.width - width, Math.max(0, threadFill.width - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 8 * root.s
            height: 8 * root.s
            radius: width / 2
            color: Theme.cream
        }
    }
}
