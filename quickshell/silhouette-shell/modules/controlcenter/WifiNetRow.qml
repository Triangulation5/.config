pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.services
import qs.components.icons

/**
 * Single network row for the wifi drill-in's list, carrying every state a row
 * can show: plain, inline confirm (connect/disconnect + reveal + forget), the
 * saved-password reveal, and the password prompt. Pure view — the list state
 * comes in as props and every action goes back out as a signal, so delegates
 * keep their identity across rescans without owning any network logic.
 */
Column {
    id: row

    required property var modelData
    required property int index

    property real s: 1.1
    property bool known: false
    property bool secured: false
    property bool expanded: false
    property bool focused: false
    property int confirmFocus: -1
    property bool revealed: false
    property string revealedPw: ""
    property bool revealResolved: false
    property string pwDraft: ""
    property bool connecting: false
    property bool connectFailed: false
    /** The list Flickable, for scroll-into-view on focus/expansion. */
    property var flick: null

    readonly property string ssid: (modelData && modelData.name) ? modelData.name : ""
    readonly property bool isActive: modelData ? modelData.connected === true : false
    readonly property bool confirming: expanded && (isActive || known)
    readonly property bool asking: expanded && !confirming
    readonly property bool focusPrimary: confirmFocus === 0
    readonly property bool focusReveal: known && confirmFocus === 1
    readonly property bool focusForget: confirmFocus === (known ? 2 : 1)

    signal requestActivate()
    signal requestConnectKnown()
    signal requestDisconnect()
    signal requestForget()
    signal requestReveal()
    signal requestConnectWithPassword(string pw)
    signal requestFocus()

    width: parent ? parent.width : 0
    spacing: 2 * s

    function syncPwField() {
        pwField.text = row.pwDraft;
        pwField.cursorPosition = pwField.text.length;
        pwField.forceActiveFocus();
    }

    /**
     * Keep the keyboard-focused (or just-expanded) row in view when the list
     * overflows its fixed-height frame. `mapToItem` gives viewport coords, so
     * scroll by the deficit against the visible bounds.
     */
    function ensureVisible() {
        if (!row.flick)
            return;
        var y = row.mapToItem(row.flick, 0, 0).y;
        var h = row.height;
        if (y < 0)
            row.flick.contentY += y;
        else if (y + h > row.flick.height)
            row.flick.contentY += y + h - row.flick.height;
    }
    onFocusedChanged: if (focused) Qt.callLater(row.ensureVisible)
    onExpandedChanged: {
        if (expanded) Qt.callLater(row.ensureVisible);
        if (asking) Qt.callLater(syncPwField);
    }
    Component.onCompleted: if (asking) Qt.callLater(syncPwField)

    Rectangle {
        width: parent.width
        height: 30 * row.s
        radius: 9 * row.s
        color: row.isActive ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.14)
            : ((rowHover.hovered || row.focused) ? Theme.frameBg : "transparent")

        HoverHandler {
            id: rowHover
            onHoveredChanged: if (hovered) row.requestFocus()
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.requestActivate()
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10 * row.s
            anchors.right: rowRight.left
            anchors.rightMargin: 8 * row.s
            anchors.verticalCenter: parent.verticalCenter
            text: row.ssid.length ? row.ssid : "Hidden"
            color: row.isActive ? Theme.vermLit : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 11.5 * row.s
            font.weight: row.isActive ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        Row {
            id: rowRight
            anchors.right: parent.right
            anchors.rightMargin: 10 * row.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7 * row.s

            Item {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -1.4 * row.s
                visible: row.secured
                width: 14 * row.s
                height: 14 * row.s

                GlyphIcon {
                    anchors.fill: parent
                    name: "lock-outline"
                    color: row.isActive ? Theme.vermLit : Theme.iconDim
                    stroke: 1.9
                }
            }

            WifiGlyph {
                anchors.verticalCenter: parent.verticalCenter
                width: 15 * row.s
                height: 15 * row.s
                s: row.s
                on: true
                level: (row.modelData && row.modelData.signalStrength) || 0
            }
        }
    }

    Item {
        visible: row.confirming
        width: parent.width
        height: 30 * row.s

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10 * row.s
            anchors.right: confirmBtns.left
            anchors.rightMargin: 8 * row.s
            anchors.verticalCenter: parent.verticalCenter
            text: row.isActive ? "Connected" : "Saved network"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * row.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Row {
            id: confirmBtns
            anchors.right: parent.right
            anchors.rightMargin: 10 * row.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * row.s

            Rectangle {
                id: primaryBtn
                anchors.verticalCenter: parent.verticalCenter
                width: primaryLabel.implicitWidth + 20 * row.s
                height: 22 * row.s
                radius: 7 * row.s
                color: (primaryArea.containsMouse || row.focusPrimary) ? Theme.tileBg : "transparent"
                border.width: 1
                border.color: (primaryArea.containsMouse || row.focusPrimary) ? Theme.vermDim : Theme.border

                Text {
                    id: primaryLabel
                    anchors.centerIn: parent
                    text: row.isActive ? "Disconnect" : "Connect"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 10 * row.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3 * row.s
                }

                MouseArea {
                    id: primaryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.isActive ? row.requestDisconnect() : row.requestConnectKnown()
                }
            }

            Rectangle {
                id: revealBtn
                anchors.verticalCenter: parent.verticalCenter
                visible: row.known
                readonly property bool shown: row.revealed
                width: revealLabel.implicitWidth + 20 * row.s
                height: 22 * row.s
                radius: 7 * row.s
                color: (revealArea.containsMouse || row.focusReveal) ? Theme.tileBg : "transparent"
                border.width: 1
                border.color: (revealBtn.shown || revealArea.containsMouse || row.focusReveal)
                    ? Theme.vermDim
                    : Theme.border

                Text {
                    id: revealLabel
                    anchors.centerIn: parent
                    text: revealBtn.shown ? "Hide" : "Show"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 10 * row.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3 * row.s
                }

                MouseArea {
                    id: revealArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.requestReveal()
                }
            }

            Rectangle {
                id: forgetBtn
                anchors.verticalCenter: parent.verticalCenter
                width: forgetLabel.implicitWidth + 20 * row.s
                height: 22 * row.s
                radius: 7 * row.s
                color: (forgetArea.containsMouse || row.focusForget)
                    ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.2)
                    : Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(Theme.vermLit.r, Theme.vermLit.g, Theme.vermLit.b, 0.45)

                Text {
                    id: forgetLabel
                    anchors.centerIn: parent
                    text: "Forget"
                    color: Theme.vermLit
                    font.family: Theme.font
                    font.pixelSize: 10 * row.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3 * row.s
                }

                MouseArea {
                    id: forgetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.requestForget()
                }
            }
        }
    }

    Item {
        readonly property bool shown: row.confirming && row.revealed
        visible: shown
        width: parent.width
        height: shown ? 24 * row.s : 0

        Text {
            id: revealCaption
            anchors.left: parent.left
            anchors.leftMargin: 10 * row.s
            anchors.verticalCenter: parent.verticalCenter
            text: "PASSWORD"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9 * row.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * row.s
        }

        Text {
            visible: row.revealResolved && row.revealedPw.length === 0
            anchors.right: parent.right
            anchors.rightMargin: 10 * row.s
            anchors.verticalCenter: parent.verticalCenter
            text: "no saved password"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10 * row.s
            font.weight: Font.Medium
        }

        TextEdit {
            visible: row.revealedPw.length > 0
            anchors.left: revealCaption.right
            anchors.leftMargin: 10 * row.s
            anchors.right: parent.right
            anchors.rightMargin: 10 * row.s
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: TextEdit.AlignRight
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.verm
            wrapMode: TextEdit.NoWrap
            clip: true
            text: row.revealed ? row.revealedPw : ""
            color: Theme.flameCore
            font.family: Theme.font
            font.pixelSize: 11.5 * row.s
            font.weight: Font.Medium
        }
    }

    Item {
        visible: row.asking
        width: parent.width
        height: 30 * row.s

        TextField {
            id: pwField
            anchors.left: parent.left
            anchors.leftMargin: 10 * row.s
            anchors.right: pwRight.left
            anchors.rightMargin: 8 * row.s
            anchors.verticalCenter: parent.verticalCenter
            background: null
            padding: 0
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11.5 * row.s
            echoMode: TextInput.Password
            placeholderText: "Password"
            placeholderTextColor: Theme.faint
            selectByMouse: true
            selectionColor: Theme.verm
            onTextEdited: row.pwDraft = text
            onAccepted: row.requestConnectWithPassword(text)
        }

        Row {
            id: pwRight
            anchors.right: parent.right
            anchors.rightMargin: 10 * row.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7 * row.s

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.connecting && row.asking
                width: 4 * row.s
                height: 4 * row.s
                radius: width / 2
                color: Theme.flameGlow

                SequentialAnimation on opacity {
                    running: row.connecting && row.asking
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                }
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * row.s
                height: 14 * row.s
                name: "return"
                color: enterArea.containsMouse ? Theme.cream : Theme.vermLit
                stroke: 1.8

                MouseArea {
                    id: enterArea
                    anchors.fill: parent
                    anchors.margins: -6 * row.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.requestConnectWithPassword(pwField.text)
                }
            }
        }
    }

    Text {
        visible: row.asking && row.connectFailed
        text: "Connection failed"
        color: Theme.vermLit
        font.family: Theme.font
        font.pixelSize: 9.5 * row.s
        leftPadding: 10 * row.s
    }
}
