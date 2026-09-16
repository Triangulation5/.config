import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services
import qs.modules.settingsapp.components

/**
 * The Backups page body: the shell's own config, snapshotted on request and put
 * back on request.
 *
 * What is in a backup, and what a restore does with it, is the script's business
 * (see Backups and utils/backup.py); this page is the face on it — a status, one
 * button to take a snapshot, and a row per archive with the two things you would
 * do with one.
 *
 * Both of those overwrite the config the shell is running from, so both are
 * behind a second click *on the row itself*: the buttons of the row you clicked
 * become a question and a cancel, and every other row stops responding while one
 * is asking. That is the same two-step the Updates page uses for the one control
 * that changes the machine — a dialog in the middle of a list is a heavier
 * interruption than the row turning into the question.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    /** The archive whose action is waiting for a second click, or "". */
    property string confirming: ""
    /** Which action that is — the service's own words: "restore" or "remove". */
    property string pending: ""

    readonly property int count: Backups.entries.length

    Component.onCompleted: Backups.refresh()

    /** The card's headline: what state this page is in, in a few words. */
    readonly property string headline: Backups.busy
        ? (Backups.action === "restore" ? "Restoring\u2026"
            : Backups.action === "create" ? "Saving\u2026"
            : "Deleting\u2026")  // the service's third verb is `remove`
        : root.count === 0 ? (Backups.ready ? "No backups yet" : "Reading\u2026")
        : root.count + " backup" + (root.count === 1 ? "" : "s") + " saved"

    /** The line under it. A refused run says why here instead of staying silent. */
    readonly property string subline: Backups.busy
        ? (Backups.action === "restore" ? "Writing the archive back over your config. The shell reloads as the files land."
            : Backups.action === "create" ? "Copying the shell and the state it keeps beside the flags."
            : "Removing the archive.")
        : Backups.note.length > 0 ? Backups.note
        : Backups.message.length > 0 ? Backups.message
        : root.count === 0 ? "A backup records the shell's own config: the tree in " + Paths.shell
            + ", plus the flags, calendar events and wallpaper it keeps in " + Paths.state + "."
        : "Archives live in " + Paths.backups + ". Restoring overwrites what an archive holds and adds back"
            + " what is missing; it never deletes a file that arrived after the backup was taken."

    /** Ask about `action` on `entry`, in place of the row's buttons. */
    function confirmFor(entry, action) {
        root.confirming = entry.name;
        root.pending = action;
    }

    function cancel() {
        root.confirming = "";
        root.pending = "";
    }

    /** The confirmed action on `entry`, and the question is answered either way. */
    function act(entry) {
        if (root.pending === "restore")
            Backups.restore(entry.name);
        else if (root.pending === "remove")
            Backups.remove(entry.name);
        root.cancel();
    }

    /** When a backup was taken — what a row is, more than its file name is. */
    function stamp(seconds) {
        return Qt.formatDateTime(new Date(seconds * 1000), "d MMM yyyy, HH:mm");
    }

    SectionLabel {
        Layout.fillWidth: true
        text: "Status"
    }

    Rectangle {
        Layout.fillWidth: true
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: statusColumn.implicitHeight + 36

        ColumnLayout {
            id: statusColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: Backups.note.length > 0 ? Theme.accent
                        : root.count === 0 ? Theme.textSecondary
                        : Theme.accent
                    opacity: Backups.busy ? 0.4 : 1

                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.headline
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: backUpLabel.implicitWidth + 26
                    implicitHeight: 30
                    radius: 8
                    opacity: Backups.busy ? 0.5 : 1
                    color: backUpMouse.containsMouse && !Backups.busy
                        ? Theme.accent : Qt.alpha(Theme.accent, 0.85)

                    Text {
                        id: backUpLabel
                        anchors.centerIn: parent
                        text: Backups.action === "create" ? "Saving\u2026" : "Back up now"
                        color: Theme.knob
                        font.pixelSize: Theme.fontSizeSection
                        font.bold: true
                    }

                    MouseArea {
                        id: backUpMouse
                        anchors.fill: parent
                        enabled: !Backups.busy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Backups.create()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.subline
                color: Backups.note.length > 0 ? Theme.accent : Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.count > 0
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: savedColumn.implicitHeight + 36

        ColumnLayout {
            id: savedColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 6

            SectionLabel {
                Layout.fillWidth: true
                text: "Saved"
            }

            Repeater {
                model: Backups.entries

                delegate: Item {
                    id: entry

                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: 46

                    readonly property bool asking: root.confirming === entry.modelData.name

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusRow
                        color: entryMouse.containsMouse && !Backups.busy && !root.confirming.length ? Theme.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.stamp(entry.modelData.created)
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeNormal
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Backups.sizeText(entry.modelData.bytes) + "  \u00B7  " + entry.modelData.name
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSection
                                elide: Text.ElideMiddle
                            }
                        }

                        // The question, asked in the row it is about.
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            visible: entry.asking
                            text: root.pending === "restore" ? "Overwrite your config?" : "Delete this backup?"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSection
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: entry.asking
                            implicitWidth: yesLabel.implicitWidth + 22
                            implicitHeight: 28
                            radius: 8
                            color: yesMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.85)

                            Text {
                                id: yesLabel
                                anchors.centerIn: parent
                                text: root.pending === "restore" ? "Restore" : "Delete"
                                color: Theme.knob
                                font.pixelSize: Theme.fontSizeSection
                                font.bold: true
                            }

                            MouseArea {
                                id: yesMouse
                                anchors.fill: parent
                                enabled: !Backups.busy
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.act(entry.modelData)
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: entry.asking
                            implicitWidth: cancelLabel.implicitWidth + 22
                            implicitHeight: 28
                            radius: 8
                            color: cancelMouse.containsMouse ? Theme.hover : "transparent"
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: cancelLabel
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSection
                            }

                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancel()
                            }
                        }

                        // Restore and Delete: what the row is for, until it asks.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: !entry.asking
                            implicitWidth: restoreLabel.implicitWidth + 22
                            implicitHeight: 28
                            radius: 8
                            opacity: root.confirming.length ? 0.4 : 1
                            color: restoreMouse.containsMouse && !root.confirming.length ? Theme.hover : Theme.searchField
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: restoreLabel
                                anchors.centerIn: parent
                                text: "Restore"
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSection
                            }

                            MouseArea {
                                id: restoreMouse
                                anchors.fill: parent
                                enabled: !Backups.busy && !root.confirming.length
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmFor(entry.modelData, "restore")
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: !entry.asking
                            implicitWidth: deleteLabel.implicitWidth + 22
                            implicitHeight: 28
                            radius: 8
                            opacity: root.confirming.length ? 0.4 : 1
                            color: deleteMouse.containsMouse && !root.confirming.length
                                ? Qt.alpha(Theme.accent, 0.16) : "transparent"
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: deleteLabel
                                anchors.centerIn: parent
                                text: "Delete"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSection
                            }

                            MouseArea {
                                id: deleteMouse
                                anchors.fill: parent
                                enabled: !Backups.busy && !root.confirming.length
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmFor(entry.modelData, "remove")
                            }
                        }
                    }
                }
            }
        }
    }
}
