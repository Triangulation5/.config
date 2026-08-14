pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.pill.surfaces
import qs.components.icons

/**
 * 鍵 polkit face: morphs the pill into a compact, centered authentication
 * dialog. Layout follows the classic auth-dialog shape — a lock badge with a
 * prominent title, the action description and muted action-id caption flush
 * left beneath it, a full-width borderless themed password field, and
 * bottom-right Cancel / Authenticate buttons — rendered entirely
 * from the shell's Theme tokens so it stays native to the pill. No caret is
 * shown (the Ame flame stays hidden here): the field is a filled grey capsule,
 * its fill and hairline border read the input even without a blinking cursor.
 * The prompt is deliberately
 * non-dismissible: while `Polkit.pending` is live, PillRoot's close() refuses
 * to fire, so Escape, backdrop presses and the hide IPC all no-op. The only
 * way out is an explicit Cancel / Authenticate (or the agent resolving the
 * conversation). Submitting writes the password back through the Polkit
 * service; polkitd runs the polkit-1 PAM stack, so biometric modules in that
 * stack (fingerprint, howdy) unlock prompts through this same face.
 */
PillSurface {
    id: root

    mTop: 0
    mLeft: 0
    mRight: 0
    mBottom: 0

    implicitHeight: col.implicitHeight + padTop + padBottom

    property bool submitted: false

    onOpenChanged: if (open) {
        root.submitted = false;
        field.text = "";
        Qt.callLater(function() { field.forceActiveFocus(); });
    }

    function submit() {
        if (root.submitted || field.text.length === 0)
            return;
        root.submitted = true;
        Polkit.respond(field.text);
    }

    function dismiss() {
        Polkit.cancel();
    }

    ameForm: "off"

    readonly property real padTop: 11 * root.s
    readonly property real padBottom: 10 * root.s
    readonly property real sidePad: 18 * root.s

    Column {
        id: col
        anchors.top: parent.top
        anchors.topMargin: root.padTop
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.sidePad
        anchors.rightMargin: root.sidePad
        spacing: 0

        Row {
            width: parent.width
            spacing: 12 * root.s

            /**
             * Lock badge, styled like the pill's IconChip: a subtle framed square
             * with the accent glyph inside, instead of a bare floating icon.
             */
            Rectangle {
                id: lockBadge
                width: 32 * root.s
                height: 32 * root.s
                radius: 9 * root.s
                color: Theme.frameBg
                border.width: 1
                border.color: Theme.frameBorder

                GlyphIcon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -0.5 * root.s
                    width: 20 * root.s
                    height: 20 * root.s
                    name: "lock"
                    color: Theme.vermLit
                    stroke: 1.7
                }
            }

            Text {
                width: parent.width - lockBadge.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "Authentication Required"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 19 * root.s
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
        }

        Item { width: 1; height: 7 * root.s }

        Text {
            width: parent.width
            text: Polkit.message.length > 0 ? Polkit.message : "Enter your password to continue"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.3
        }

        Text {
            width: parent.width
            visible: Polkit.action.length > 0
            text: Polkit.action
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Item { width: 1; height: 10 * root.s }

        Rectangle {
            id: fieldRect
            width: parent.width
            height: 38 * root.s
            radius: height / 2
            /** Lifted capsule grey + the standard tile border so the field
             * reads as a filled input against the pill body. */
            color: Qt.lighter(Theme.capsule, 1.25)
            border.width: 1
            border.color: Theme.border

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 20 * root.s
                anchors.rightMargin: 20 * root.s
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                color: "transparent"
                cursorVisible: false
                font.family: Theme.font
                font.pixelSize: 14 * root.s
                font.letterSpacing: 2 * root.s
                enabled: !root.submitted
                clip: true

                onAccepted: root.submit()

                Row {
                    anchors.centerIn: parent
                    spacing: 6 * root.s
                    visible: field.text.length > 0

                    Repeater {
                        model: field.text.length
                        Rectangle {
                            width: 8 * root.s
                            height: 8 * root.s
                            radius: width / 2
                            color: Theme.bright
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: field.text.length === 0 && !root.submitted
                    text: "<i>password</i>"
                    textFormat: Text.RichText
                    color: Theme.placeholder
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    font.letterSpacing: 1 * root.s
                }
            }
        }

        Item { width: 1; height: 7 * root.s }

        Text {
            width: parent.width
            visible: root.submitted
            horizontalAlignment: Text.AlignHCenter
            text: "Checking…"
            color: Theme.flameGlow
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 0.5 * root.s
        }

        Row {
            width: parent.width
            visible: !root.submitted
            spacing: 8 * root.s
            layoutDirection: Qt.RightToLeft

            Rectangle {
                width: 106 * root.s
                height: 30 * root.s
                radius: 9 * root.s
                color: authArea.pressed ? Qt.darker(Theme.verm, 1.18)
                    : (authArea.containsMouse ? Theme.vermLit : Theme.verm)

                Behavior on color {
                    ColorAnimation {
                        duration: 130
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Authenticate"
                    color: "#141416"
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: authArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submit()
                }
            }

            Rectangle {
                width: 76 * root.s
                height: 30 * root.s
                radius: 9 * root.s
                color: cancelArea.pressed ? Qt.darker(Theme.tileBg, 1.2)
                    : (cancelArea.containsMouse ? Theme.tileBg : "transparent")
                border.width: 1
                border.color: Theme.border

                Behavior on color {
                    ColorAnimation {
                        duration: 130
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismiss()
                }
            }
        }
    }
}
