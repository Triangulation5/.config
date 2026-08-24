pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.recording

/**
 * The Recorder's RECENT section: a header row (kanji, clip count and a
 * two-tone CLEAR action), an empty state, and the horizontal filmstrip of
 * ClipRow tiles with its wheel scrolling. `surface` is the Recorder root,
 * passed through to each ClipRow so its two-step delete badge can reach the
 * root's rmClipProc.
 */
Item {
    id: clipList

    property var surface: null
    property real s: 1

    width: parent ? parent.width : 0
    height: 16 * s + 9 * s + 64 * s


    Item {
        width: parent.width
        height: 16 * s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * s

            Text {
                visible: Flags.showGlyphs
                height: 16 * s
                verticalAlignment: Text.AlignVCenter
                text: "録"
                color: Theme.subtle
                font.family: Theme.fontJp
                font.pixelSize: 11 * s
            }
            Text {
                height: 16 * s
                verticalAlignment: Text.AlignVCenter
                text: "RECENT · " + ScreenRec.recentCount
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * s
            }
        }

        Item {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: clearTxt.width + (Flags.showGlyphs ? clearKanji.width + 5 * s : 0)
            visible: ScreenRec.recentCount > 0

            Text {
                id: clearKanji
                anchors.right: clearTxt.left
                anchors.rightMargin: 5 * s
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: "払"
                color: clearArea.containsMouse ? Theme.flameGlow : Theme.vermDeep
                font.family: Theme.fontJp
                font.pixelSize: 11 * s
            }
            Text {
                id: clearTxt
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "CLEAR"
                color: clearArea.containsMouse ? Theme.flameGlow : Theme.vermDeep
                font.family: Theme.font
                font.pixelSize: 9 * s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * s
            }

            MouseArea {
                id: clearArea
                anchors.fill: parent
                anchors.margins: -6 * s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.clearRecent()
            }
        }
    }

    Item { width: 1; height: 9 * s }


    Item {
        width: parent.width
        height: 64 * s

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: ScreenRec.recentCount === 0
            text: "No recordings yet"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * s
        }

        ListView {
            id: filmstrip
            anchors.fill: parent
            visible: ScreenRec.recentCount > 0
            orientation: ListView.Horizontal
            clip: true
            spacing: 9 * s
            boundsBehavior: Flickable.StopAtBounds
            model: ScreenRec.recent

            delegate: ClipRow {
                required property var modelData
                required property int index
                surface: clipList.surface
                s: clipList.s
                clipName: modelData.name
                clipThumb: modelData.thumb
                clipSizeLabel: modelData.sizeLabel
                clipPath: modelData.path
                rowIndex: index
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (event) => {
                var max = Math.max(0, filmstrip.contentWidth - filmstrip.width);
                filmstrip.contentX = Math.max(0, Math.min(max, filmstrip.contentX - event.angleDelta.y / 120 * 48 * clipList.s));
                event.accepted = true;
            }
        }
    }
}
