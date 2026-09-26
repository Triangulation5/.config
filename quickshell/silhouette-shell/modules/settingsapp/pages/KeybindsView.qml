import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services
import qs.modules.settingsapp.components

/**
 * The Keybinds page body: the whole binds file as a shortcut sheet.
 *
 * It only reads. Every bind the file holds gets a row — its chord as chips, its
 * name beside them and the dispatch it runs underneath — and there is not a
 * control on the page that writes: no editor, no reset, nothing to click but a
 * filter field. The rule the app keeps for its own files is that one service
 * owns the writes to a file, and the writes to this one belong to the shell's
 * keybinds surface and to the Workspaces page; a reference that cannot write
 * cannot clobber either of them.
 *
 * The list is filtered locally rather than through the rail's search, because a
 * view page has no rows for the rail to match on: the rail finds this page by
 * its keywords, and the field here finds a shortcut inside it.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    /** The filter's live query; matched against the chord, the name and the dispatch. */
    property string query: ""

    /** The binds the filter lets through, in file order. */
    readonly property var shown: {
        if (root.query.length === 0)
            return Binds.binds;
        var q = root.query.toLowerCase();
        return Binds.binds.filter(function (b) {
            return (b.combo + " " + b.label + " " + b.action).toLowerCase().indexOf(q) !== -1;
        });
    }

    /** Mouse and scroll tokens spelled out, so a gesture chip reads as one. */
    function pretty(token) {
        return token.replace("mouse_up", "Scroll \u2191")
                    .replace("mouse_down", "Scroll \u2193")
                    .replace("mouse:272", "LMB")
                    .replace("mouse:273", "RMB");
    }

    SectionLabel {
        Layout.fillWidth: true
        text: "Reference"
    }

    /**
     * What the page is looking at: how many binds, and where they came from. It
     * says out loud that the page only reads, so a missing edit control is not
     * mistaken for something that has not loaded.
     */
    Rectangle {
        Layout.fillWidth: true
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: statusColumn.implicitHeight + 36

        ColumnLayout {
            id: statusColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: Binds.count === 0
                        ? "No shortcuts found"
                        : Binds.count + " shortcut" + (Binds.count === 1 ? "" : "s") + " bound"
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Read from " + Binds.path + ". This page only reads \u2014 nothing here changes a bind;"
                    + " edit the file or open the shell's keybinds surface to do that."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
            }
        }
    }

    /** Local filter: the rail's search cannot see a view page's rows. */
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 10
        color: Theme.searchField
        border.width: 1
        border.color: filter.activeFocus ? Qt.alpha(Theme.accent, 0.35) : Theme.border

        Behavior on border.color { ColorAnimation { duration: Theme.animNormal } }

        TextInput {
            id: filter

            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            clip: true
            selectByMouse: true
            onTextChanged: root.query = text

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Filter shortcuts"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                visible: filter.text.length === 0
            }

            Keys.onEscapePressed: filter.text = ""
        }
    }

    Rectangle {
        Layout.fillWidth: true
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: listColumn.implicitHeight + 36

        ColumnLayout {
            id: listColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 0

            Repeater {
                model: root.shown

                delegate: ColumnLayout {
                    id: bindRow

                    required property var modelData
                    required property int index

                    /** The chord split into its tokens, so each can be a chip. */
                    readonly property var parts: String(modelData.combo).split(" + ")

                    Layout.fillWidth: true
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: bindRow.index > 0 ? 1 : 0
                        Layout.topMargin: bindRow.index > 0 ? 6 : 0
                        Layout.bottomMargin: bindRow.index > 0 ? 6 : 0
                        color: Theme.border
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 7
                        Layout.bottomMargin: 7
                        spacing: 14

                        /**
                         * The chord, in a fixed column so the names line up down
                         * the sheet. A minimum rather than a maximum: a long key
                         * like XF86MonBrightnessDown widens its own row instead
                         * of being clipped.
                         */
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.minimumWidth: 232
                            spacing: 4

                            Repeater {
                                model: bindRow.parts

                                delegate: Row {
                                    id: chip

                                    required property string modelData
                                    required property int index

                                    /** The last token is the key itself; the ones before it are modifiers. */
                                    readonly property bool isKey: chip.index === bindRow.parts.length - 1

                                    spacing: 4

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: chipText.width + 14
                                        height: 22
                                        radius: 6
                                        color: chip.isKey ? Qt.alpha(Theme.accent, 0.16) : Theme.hover
                                        border.width: 1
                                        border.color: chip.isKey ? Qt.alpha(Theme.accent, 0.35) : Theme.border

                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            text: root.pretty(chip.modelData)
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSizeSection
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !chip.isKey
                                        text: "+"
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSection
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: bindRow.modelData.label
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeNormal
                                elide: Text.ElideRight
                            }

                            /** What the file actually runs, and the flags worth knowing about. */
                            Text {
                                Layout.fillWidth: true
                                text: bindRow.modelData.action
                                    + (bindRow.modelData.locked ? "  \u00B7  locked" : "")
                                    + (bindRow.modelData.repeating ? "  \u00B7  repeating" : "")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSection
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: root.shown.length === 0
                text: Binds.count === 0
                    ? "Nothing to show \u2014 " + Binds.path + " holds no binds."
                    : "No shortcut matches \u201C" + root.query + "\u201D."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
            }
        }
    }
}
