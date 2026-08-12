pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.services
import qs.components.icons

/**
 * One recording clip row in the Recorder's filmstrip. All data is passed
 * from the delegate body where both root and the ListView model data
 * are directly accessible.
 */
Item {
    id: frame

    property var surface: null
    property real s: 1
    property string clipName: ""
    property string clipThumb: ""
    property string clipSizeLabel: ""
    property string clipPath: ""
    property int rowIndex: -1

    /* ── Derived display strings ──────────────────────────────── */

    readonly property string stamp: {
        var m = /_(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})/.exec(frame.clipName);
        return m ? m[2] + "-" + m[3] + " " + m[4] + ":" + m[5]
                 : frame.clipName.replace("recording_", "").replace(".mp4", "");
    }
    readonly property bool coverReady: cover.status === Image.Ready && cover.source !== ""

    property bool armed: false

    width: 108 * s
    height: parent ? parent.height : implicitHeight
    implicitHeight: thumb.height + meta.height

    /* ── Thumbnail tile ────────────────────────────────────────── */

    ClippingRectangle {
        id: thumb
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48 * s
        radius: 9 * s
        color: Theme.tileBg

        Rectangle {
            anchors.fill: parent
            visible: !frame.coverReady
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.cardTop }
                GradientStop { position: 1.0; color: Theme.tileBg }
            }
        }

        Image {
            id: cover
            anchors.fill: parent
            source: frame.clipThumb ? "file://" + frame.clipThumb : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize.width: 216 * s
            sourceSize.height: 96 * s
        }

        GlyphIcon {
            anchors.centerIn: parent
            width: 14 * s
            height: 14 * s
            visible: !frame.coverReady
            name: "play"
            color: frameArea.containsMouse ? Theme.cream : Theme.iconDim
        }

        Rectangle {
            anchors.centerIn: parent
            width: 22 * s
            height: 22 * s
            radius: width / 2
            visible: frame.coverReady
            color: Qt.rgba(0, 0, 0, 0.34)
            opacity: frameArea.containsMouse ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            GlyphIcon {
                anchors.centerIn: parent
                width: 11 * s
                height: 11 * s
                name: "play"
                color: Theme.cream
            }
        }
    }

    Rectangle {
        anchors.fill: thumb
        radius: thumb.radius
        color: "transparent"
        border.width: 1.5
        border.color: frame.rowIndex === 0 ? Qt.alpha(Theme.vermLit, 0.4)
            : (frameArea.containsMouse ? Theme.vermDim : Theme.border)
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    }

    /* ── Timestamp + size row ──────────────────────────────────── */

    Item {
        id: meta
        anchors.top: thumb.bottom
        anchors.topMargin: 5 * s
        anchors.left: parent.left
        anchors.right: parent.right
        height: stampTxt.height

        Text {
            id: stampTxt
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: sizeTxt.left
            anchors.rightMargin: 4 * s
            text: frame.stamp
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * s
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            id: sizeTxt
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: frame.clipSizeLabel
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 8.5 * s
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    /* ── Open-on-click area ────────────────────────────────────── */

    MouseArea {
        id: frameArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ScreenRec.openFile(frame.clipPath)
    }

    /* ── Two-step delete badge ──────────────────────────────────── */

    Rectangle {
        id: delBadge
        anchors.top: thumb.top
        anchors.right: thumb.right
        anchors.margins: 4 * s
        width: 15 * s
        height: 15 * s
        radius: width / 2
        color: frame.armed ? "#e0533f" : Qt.rgba(0, 0, 0, 0.4)
        opacity: frameArea.containsMouse || delClipArea.containsMouse ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        GlyphIcon {
            anchors.centerIn: parent
            width: 8 * s
            height: 8 * s
            name: "close"
            stroke: 2
            color: frame.armed || delClipArea.containsMouse ? Theme.cream : Theme.dim
        }

        MouseArea {
            id: delClipArea
            anchors.fill: parent
            anchors.margins: -4 * s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onExited: frame.armed = false
            onClicked: {
                if (!frame.armed) {
                    frame.armed = true;
                    return;
                }
                frame.armed = false;
                if (surface && surface.rmClipProc) {
                    surface.rmClipProc.command = ["rm", "--", frame.clipPath];
                    surface.rmClipProc.running = true;
                }
            }
        }
    }
}
