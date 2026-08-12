pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components.controls
import qs.components.icons

/**
 * 報 INBOX section of the LINK surface: a header row (kanji + CLEAR), the
 * notification group list — per-app heads with expand/collapse, dismiss and
 * preview, plus critical rows above them — and the 静 SILENCE empty state.
 * Hover and close events are forwarded to the host so the pill's row seam and
 * surface close keep working.
 */
Item {
    id: inbox

    property real s: 1

    /** Forwarded from rows and group heads; the host parks its focus seam there. */
    signal reportRowHover(Item item, bool hovered)
    /** A NotifRow asked to close the surface (e.g. an action button). */
    signal requestClose()

    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4 * s

        Item {
            width: parent.width
            height: 20 * s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * s

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10 * s
                    height: 10 * s
                }

                Text {
                    id: inboxKanji
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "報"
                    color: Theme.dim
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 11.5 * s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Flags.showGlyphs ? "INBOX" : "Notifications"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * s
                    font.weight: Font.Bold
                    font.letterSpacing: Flags.showGlyphs ? 1.8 * s : 0.8 * s
                }
            }

            Row {
                id: clearRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifs.count > 0
                spacing: 4 * s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "払"
                    color: clearArea.containsMouse ? Theme.vermLit : Theme.vermDim
                    font.family: Theme.fontJp
                    font.pixelSize: 9 * s
                    font.weight: Font.Bold
                }
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !Flags.showGlyphs
                    width: 11 * s
                    height: 11 * s
                    name: "trash"
                    color: clearArea.containsMouse ? Theme.vermLit : Theme.vermDim
                    stroke: 1.8
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CLEAR"
                    color: clearArea.containsMouse ? Theme.vermLit : Theme.vermDim
                    font.family: Theme.font
                    font.pixelSize: 9 * s
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4 * s
                }
            }

            MouseArea {
                id: clearArea
                anchors.fill: clearRow
                anchors.margins: -5 * s
                visible: Notifs.count > 0
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.clearAll()
            }
        }

        Item {
            visible: Notifs.count > 0
            width: parent.width
            height: notifFlick.height

            Flickable {
                id: notifFlick
                width: parent.width
                height: Math.min(notifCol.implicitHeight, 320 * s)
                contentHeight: notifCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: returnToBounds()

                Column {
                    id: notifCol
                    width: notifFlick.width
                    spacing: 6 * s

                    Repeater {
                        model: Notifs.groups

                        Column {
                            id: group
                            required property var modelData
                            readonly property bool expanded: Notifs.expandedApps[modelData.app] === true
                            width: notifCol.width
                            spacing: 2 * s

                            Repeater {
                                model: group.modelData.criticals

                                NotifRow {
                                    required property var modelData
                                    s: inbox.s
                                    entry: modelData
                                    critical: true
                                    onReportHover: (item, hovered) => inbox.reportRowHover(item, hovered)
                                    onRequestClose: inbox.requestClose()
                                }
                            }

                            Rectangle {
                                id: groupHead
                                width: parent.width
                                height: 32 * s
                                radius: 8 * s
                                color: headHover.hovered ? Theme.frameBg : "transparent"

                                HoverHandler {
                                    id: headHover
                                    onHoveredChanged: inbox.reportRowHover(groupHead, hovered)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.toggleExpanded(group.modelData.app)
                                }

                                Rectangle {
                                    id: headTile
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20 * s
                                    height: 20 * s
                                    radius: 6 * s
                                    color: Theme.tileBg
                                    border.width: 1
                                    border.color: Theme.border

                                    Image {
                                        id: headImg
                                        anchors.fill: parent
                                        anchors.margins: group.modelData.newest.image ? 0 : 3 * s
                                        source: Notifs.iconFor(group.modelData.newest)
                                        sourceSize.width: 40
                                        sourceSize.height: 40
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        asynchronous: true
                                        visible: source.toString().length > 0
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: !headImg.visible
                                        width: 6 * s
                                        height: 6 * s
                                        radius: 2 * s
                                        rotation: 45
                                        color: Theme.verm
                                    }
                                }

                                Text {
                                    id: headName
                                    anchors.left: headTile.right
                                    anchors.leftMargin: 8 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, 110 * s)
                                    text: group.modelData.app
                                    color: Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 9 * s
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1.2 * s
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: headCount
                                    anchors.left: headName.right
                                    anchors.leftMargin: 5 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "· " + group.modelData.count
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9 * s
                                }

                                Text {
                                    anchors.left: headCount.right
                                    anchors.leftMargin: 8 * s
                                    anchors.right: headX.left
                                    anchors.rightMargin: 8 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: group.modelData.preview.body.length > 0
                                        ? group.modelData.preview.body
                                        : group.modelData.preview.summary
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 10 * s
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    textFormat: Text.PlainText
                                }

                                GlyphIcon {
                                    id: headChev
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 11 * s
                                    height: 11 * s
                                    name: group.expanded ? "chevron-down" : "chevron-right"
                                    color: Theme.faint
                                    stroke: 2
                                }

                                GlyphIcon {
                                    id: headX
                                    anchors.right: headChev.left
                                    anchors.rightMargin: 7 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 11 * s
                                    height: 11 * s
                                    opacity: headHover.hovered ? 1 : 0
                                    name: "close"
                                    color: headXArea.containsMouse ? Theme.cream : Theme.dim
                                    stroke: 1.9
                                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                    MouseArea {
                                        id: headXArea
                                        anchors.fill: parent
                                        anchors.margins: -6 * s
                                        enabled: headHover.hovered
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Notifs.dismissApp(group.modelData.app)
                                    }
                                }
                            }

                            Column {
                                visible: group.expanded
                                width: parent.width
                                spacing: 2 * s

                                Repeater {
                                    model: group.expanded ? group.modelData.entries : []

                                    NotifRow {
                                        required property var modelData
                                        s: inbox.s
                                        entry: modelData
                                        onReportHover: (item, hovered) => inbox.reportRowHover(item, hovered)
                                        onRequestClose: inbox.requestClose()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            WheelScroller {
                anchors.fill: parent
                s: inbox.s
                flick: notifFlick
            }
        }

        Column {
            visible: Notifs.count === 0
            width: parent.width
            topPadding: 14 * s
            bottomPadding: 14 * s
            spacing: 4 * s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Flags.showGlyphs
                text: "静"
                color: Theme.ghost
                opacity: 0.55
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 32 * s
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Flags.showGlyphs ? "SILENCE" : "No notifications to display"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * s
                font.weight: Font.Bold
                font.letterSpacing: Flags.showGlyphs ? 2.2 * s : 0.8 * s
            }
        }
    }
}
