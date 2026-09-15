import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../config"

/**
 * ContentArea: back/forward nav, page title, and the selected page's cards —
 * rendered data-driven from the Pages model. Every editor binds through the
 * Store singleton, so a change lands in flags.json and the live shell
 * applies it instantly. The floating "Reset to Defaults" button restores
 * every row on the current page to its `reset` value.
 */
Item {
    id: root

    property int pageIndex: 0
    readonly property var page: Pages.pages[pageIndex]
    readonly property string pageTitle: page ? page.name : ""

    /** Restore every row on the current page to its reset value. */
    function resetCurrentPage() {
        if (!page)
            return;
        for (var g = 0; g < page.groups.length; g++) {
            var rows = page.groups[g].rows;
            for (var r = 0; r < rows.length; r++) {
                var row = rows[r];
                if (row.reset !== undefined)
                    Store.set(row.key, row.reset);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 20

        // Back / forward + title
        RowLayout {
            spacing: 8

            Repeater {
                model: [{ glyph: "\u2039", dir: -1 }, { glyph: "\u203A", dir: 1 }]

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    readonly property bool atEnd: (modelData.dir < 0 && root.pageIndex === 0)
                        || (modelData.dir > 0 && root.pageIndex === Pages.pages.length - 1)

                    width: 28
                    height: 28
                    radius: 8
                    color: navMouse.containsMouse && !atEnd ? Theme.hover : Theme.navButton
                    border.width: 1
                    border.color: atEnd ? Qt.rgba(1, 1, 1, 0.02) : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.glyph
                        color: parent.atEnd ? Qt.rgba(1, 1, 1, 0.12) : Theme.textSecondary
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.atEnd ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            var next = root.pageIndex + parent.modelData.dir;
                            if (next >= 0 && next < Pages.pages.length)
                                root.pageIndex = next;
                        }
                    }
                }
            }

            Text {
                text: root.pageTitle
                color: Theme.text
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                Layout.leftMargin: 10
            }

            Item { Layout.fillWidth: true }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: root.width - 56
                spacing: 22

                // Section groups of the current page: optional section label
                // above each rounded card, rows inside the card.
                Repeater {
                    model: root.page ? root.page.groups : []

                    delegate: ColumnLayout {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            visible: (modelData.title || "").length > 0
                            text: modelData.title || ""
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSection
                            leftPadding: 4
                        }

                        SettingCard {
                            Layout.fillWidth: true

                            ColumnLayout {
                                width: parent.width
                                spacing: 18

                                Repeater {
                                    model: modelData.rows

                                    delegate: Loader {
                                        required property int index
                                        required property var modelData
                                        Layout.fillWidth: true
                                        sourceComponent: modelData.type === "toggle" ? toggleComp
                                            : modelData.type === "slider" ? sliderComp
                                            : modelData.type === "segmented" ? segComp
                                            : textComp

                                        Component {
                                            id: toggleComp

                                            SettingToggle {
                                                label: modelData.label
                                                caption: modelData.caption || ""
                                                checked: Store.adapter[modelData.key]
                                                onCommit: function(b) { Store.set(modelData.key, b) }
                                            }
                                        }

                                        Component {
                                            id: sliderComp

                                            SettingSlider {
                                                label: modelData.label
                                                value: Store.adapter[modelData.key]
                                                from: modelData.min
                                                to: modelData.max
                                                step: modelData.step
                                                unit: modelData.unit || "px"
                                                displayScale: modelData.displayScale || 1
                                                onCommit: function(v) { Store.set(modelData.key, v) }
                                            }
                                        }

                                        Component {
                                            id: segComp

                                            RowLayout {
                                                spacing: 4

                                                Repeater {
                                                    model: modelData.names

                                                    delegate: Rectangle {
                                                        required property int index
                                                        required property var modelData
                                                        readonly property bool on: Store.adapter[segRow.row.key] === segRow.row.options[index]

                                                        implicitWidth: segText.implicitWidth + 20
                                                        implicitHeight: 24
                                                        radius: 7
                                                        color: on ? Theme.accent : (segMouse.containsMouse ? Theme.hover : Theme.navButton)
                                                        border.width: 1
                                                        border.color: Theme.border
                                                        Behavior on color { ColorAnimation { duration: Theme.animNormal } }

                                                        Text {
                                                            id: segText
                                                            anchors.centerIn: parent
                                                            text: parent.modelData
                                                            color: parent.on ? Theme.knob : Theme.textSecondary
                                                            font.pixelSize: Theme.fontSizeSection
                                                            font.bold: true
                                                        }

                                                        MouseArea {
                                                            id: segMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: Store.set(segRow.row.key, segRow.row.options[parent.index])
                                                        }
                                                    }
                                                }

                                                // Hidden holder for the row def.
                                                Item {
                                                    id: segRow
                                                    property var row: modelData
                                                    width: 0; height: 0; visible: false
                                                }
                                            }
                                        }

                                        Component {
                                            id: textComp

                                            RowLayout {
                                                spacing: 12

                                                Text {
                                                    text: modelData.label
                                                    color: Theme.text
                                                    font.pixelSize: Theme.fontSizeNormal
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }

                                                TextField {
                                                id: textField
                                                property var row: modelData
                                                Layout.preferredWidth: 220
                                                color: Theme.text
                                                font.pixelSize: Theme.fontSizeSmall
                                                text: Store.adapter[row.key]
                                                placeholderText: row.placeholder || ""
                                                placeholderTextColor: Theme.textSecondary
                                                selectByMouse: true

                                                background: Rectangle {
                                                    radius: 8
                                                    color: Theme.searchField
                                                    border.width: 1
                                                    border.color: textField.activeFocus ? Qt.rgba(0.616, 0.8, 0.604, 0.45) : Theme.border
                                                    Behavior on border.color { ColorAnimation { duration: Theme.animNormal } }
                                                }

                                                onEditingFinished: Store.set(row.key, text)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Extra breathing room so the floating reset button never
                // sits on top of the last card while scrolled to the bottom.
                Item { Layout.preferredHeight: 56 }
            }
        }
    }

    // Floating "Reset to Defaults" — pinned to the bottom-right of the
    // content area on every page, independent of scroll position.
    Rectangle {
        id: resetButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 28
        anchors.bottomMargin: 24
        radius: 10
        implicitHeight: 34
        implicitWidth: resetRow.implicitWidth + 28
        color: resetMouse.containsMouse ? "#1c1c1c" : Theme.navButton
        border.width: 1
        border.color: Theme.border
        scale: resetMouse.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: Theme.animNormal } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

        RowLayout {
            id: resetRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: "\u27F2"
                color: Theme.textSecondary
                font.pixelSize: 14
                rotation: resetMouse.pressed ? -60 : 0
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }

            Text {
                text: "Reset to Defaults"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resetCurrentPage()
        }
    }
}
