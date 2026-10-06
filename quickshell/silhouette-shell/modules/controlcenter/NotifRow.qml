pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs.services
import qs.components.icons
import qs.components.controls

/**
 * Single inbox entry for the Link surface: icon tile or diamond, body text,
 * ×N coalesce badge, age label that cross-fades into a dismiss glyph on hover.
 * Critical entries gain a vermilion left hairline and cream emphasis. When a
 * reply action exists, a reply glyph appears on hover; clicking it reveals an
 * inline TextField — Enter sends the reply, Escape cancels.
 *
 * A click opens the row: the text wraps over as many lines as it needs and the
 * row grows to fit, so a long message can actually be read. A double-click is
 * what still opens the app behind the notification. The open state is held on
 * Notifs (keyed by notification id) so a new notification rebuilding the group
 * list does not collapse the row being read.
 */
Rectangle {
    id: nrow

    property real s: 1.1

    required property var entry
    property bool critical: false
    readonly property var n: entry.n
    readonly property var replyAct: Notifs.replyAction(n)
    readonly property bool hasReply: replyAct !== null
    /**
     * The default action's label once the row is open, or "" when the
     * notification has none (or the row is collapsed).
     */
    readonly property string actLabel: nrow.expanded ? Notifs.defaultActionLabel(n) : ""
    property bool replying: false
    /**
     * Read straight off the service map rather than through
     * `Notifs.entryExpanded()`: a property read hidden inside a called function
     * is not captured by this binding, so the row would never repaint (the same
     * trap `ageLabel` sidesteps with its `tick` read).
     */
    readonly property bool expanded: Notifs.expandedEntries[String(n.id)] === true

    /** Emitted when the row is hovered/unhovered, for soul-seam tracking. */
    signal reportHover(Item item, bool hovered)
    /** Emitted when the notification is activated and the surface should close. */
    signal requestClose()

    width: parent ? parent.width : 0
    height: replying ? 52 * s : (expanded ? Math.max(26 * s, nrowStack.implicitHeight + 18 * s) : 26 * s)
    radius: 7 * s
    color: nrowHover.hovered ? Theme.frameBg : "transparent"

    Behavior on height { NumberAnimation { duration: Motion.fast } }

    onReplyingChanged: if (replying) Qt.callLater(function() { replyField.forceActiveFocus(); })

    HoverHandler {
        id: nrowHover
        onHoveredChanged: {
            nrow.reportHover(nrow, hovered);
            if (!hovered && !nrow.replying)
                nrow.replying = false;
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (nrow.replying)
                return;
            Notifs.toggleEntry(nrow.entry);
        }
        onDoubleClicked: {
            if (nrow.replying)
                return;
            Notifs.activateEntry(nrow.entry);
            nrow.requestClose();
        }
    }

    Rectangle {
        visible: nrow.critical
        anchors.left: parent.left
        anchors.leftMargin: 1 * s
        anchors.verticalCenter: parent.verticalCenter
        width: 2 * s
        height: parent.height - 10 * s
        radius: 999
        color: Theme.verm
    }

    /**
     * ClippingRectangle clips the image to the rounded corners (plain
     * Rectangle `clip` only clips to the square bounds, leaving the image's
     * corners poking past the radius).
     */
    ClippingRectangle {
        id: nrowTile
        anchors.left: parent.left
        anchors.leftMargin: 8 * s
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * s
        height: 16 * s
        radius: 5 * s
        color: Theme.tileBg
        border.width: 1
        border.color: Theme.border

        Image {
            id: nrowImg
            anchors.fill: parent
            anchors.margins: n.image ? 0 : 2 * s
            source: Notifs.iconFor(n)
            sourceSize.width: 40
            sourceSize.height: 40
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            visible: source.toString().length > 0
        }

        Rectangle {
            anchors.centerIn: parent
            visible: !nrowImg.visible
            width: 5 * s
            height: 5 * s
            radius: 1.5 * s
            rotation: 45
            color: nrow.critical ? Theme.vermLit : Theme.verm
        }
    }

    /**
     * Text and action pill stacked. A Column rather than two independently
     * positioned items because the row's height is derived from what the open
     * content needs, and a vertically-centred Text fights an absolutely
     * positioned pill below it as soon as the row grows past two lines.
     */
    Column {
        id: nrowStack
        /**
         * The reply field is absolutely positioned over the row's lower half,
         * so the stack steps aside for it rather than the two overlapping.
         */
        visible: !nrow.replying
        anchors.left: nrowTile.right
        anchors.leftMargin: 8 * s
        anchors.right: nrowRight.left
        anchors.rightMargin: 8 * s
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 16 * s - nrowRight.width - 8 * s
        spacing: nrow.expanded ? 6 * s : 0

        Text {
            id: nrowText
            width: parent.width
            /**
             * Collapsed it is one elided line; open it wraps, and the row's
             * height binding above grows to whatever this ends up needing.
             */
            text: n.body.length > 0 ? n.body : n.summary
            color: nrow.critical ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * s
            font.weight: nrow.critical ? Font.DemiBold : Font.Medium
            wrapMode: nrow.expanded ? Text.Wrap : Text.NoWrap
            elide: Text.ElideRight
            maximumLineCount: nrow.expanded ? 20 : 1
            textFormat: Text.PlainText
        }

        /**
         * The default action, as a pill under the text. Until now it was only
         * reachable by double-clicking the row, which the row advertises
         * nowhere -- a long notification had no visible way to jump to the app
         * behind it.
         */
        Rectangle {
            id: nrowAct
            visible: nrow.actLabel.length > 0
            height: 20 * s
            width: Math.min(nrowActText.implicitWidth + 16 * s, parent.width)
            radius: 999
            color: actHover.hovered ? Theme.frameBg : Theme.tileBg
            border.width: 1
            border.color: Theme.border
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Text {
                id: nrowActText
                anchors.centerIn: parent
                text: nrow.actLabel
                color: Theme.vermLit
                font.family: Theme.font
                font.pixelSize: 9.5 * s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            HoverHandler { id: actHover }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Notifs.activateEntry(nrow.entry);
                    nrow.requestClose();
                }
            }
        }
    }

    Row {
        id: nrowRight
        anchors.right: parent.right
        anchors.rightMargin: 8 * s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6 * s

        Text {
            visible: nrow.entry.count > 1
            anchors.verticalCenter: parent.verticalCenter
            text: "×" + nrow.entry.count
            color: nrow.critical ? Theme.vermLit : Theme.vermDim
            font.family: Theme.font
            font.pixelSize: 9 * s
            font.weight: Font.Bold
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(nrowAge.implicitWidth, nrowIcons.width)
            height: Math.max(nrowAge.implicitHeight, nrowIcons.height)

            Text {
                id: nrowAge
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                opacity: nrowHover.hovered ? 0 : 1
                text: Notifs.ageLabel(n)
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * s
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }

            Row {
                id: nrowIcons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * s
                opacity: nrowHover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                HoverIcon {
                    id: nrowReply
                    visible: nrow.hasReply
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11 * s
                    height: 11 * s
                    name: "return"
                    color: Theme.dim
                    hoverColor: Theme.vermLit
                    stroke: 1.9
                    hitPad: 6 * s
                    enabled: nrowHover.hovered && nrow.hasReply
                    onClicked: nrow.replying = true
                }

                HoverIcon {
                    id: nrowX
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11 * s
                    height: 11 * s
                    name: "close"
                    color: Theme.dim
                    hoverColor: Theme.cream
                    stroke: 1.9
                    hitPad: 6 * s
                    enabled: nrowHover.hovered
                    onClicked: Notifs.dismissEntry(nrow.entry)
                }
            }
        }
    }

    Item {
        visible: nrow.replying
        anchors.left: nrowTile.right
        anchors.leftMargin: 8 * s
        anchors.right: parent.right
        anchors.rightMargin: 8 * s
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4 * s
        height: 22 * s

        Rectangle {
            anchors.fill: parent
            radius: 5 * s
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: replyField.activeFocus ? Theme.vermDim : Theme.border
        }

        TextInput {
            id: replyField
            anchors.fill: parent
            anchors.leftMargin: 8 * s
            anchors.rightMargin: 8 * s
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * s
            selectByMouse: true
            clip: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    var text = replyField.text.trim();
                    if (text.length > 0 && nrow.replyAct) {
                        nrow.replyAct.invoke(text);
                        Notifs.dismissEntry(nrow.entry);
                    }
                    nrow.replying = false;
                    e.accepted = true;
                } else if (e.key === Qt.Key_Escape) {
                    nrow.replying = false;
                    e.accepted = true;
                }
            }
        }
    }
}
