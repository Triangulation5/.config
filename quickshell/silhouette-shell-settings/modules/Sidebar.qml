import QtQuick
import QtQuick.Layouts
import "../config"

/**
 * Sidebar: search field + nav list driven by the Pages model. Typing filters
 * the list live (page name + row labels/captions); with a query, only pages
 * containing matching rows are shown. Selection still opens the page.
 */
Rectangle {
    id: root
    color: Theme.sidebar

    property int currentIndex: 0
    property string query: ""

    readonly property var visiblePages: {
        var hits = Pages.searchPages(query);
        if (hits === null)
            return Pages.pages;
        var out = [];
        for (var i = 0; i < hits.length; i++)
            out.push(Pages.pages[hits[i].index]);
        return out;
    }

    // divider between sidebar and content
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        spacing: 6

        // Search field
        Rectangle {
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 10
            color: Theme.searchField

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                Text {
                    text: "\u2315"
                    color: Theme.textSecondary
                    font.pixelSize: 14
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    clip: true
                    selectByMouse: true

                    onTextChanged: root.query = text

                    Text {
                        text: "Search Settings"
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        visible: searchInput.text.length === 0
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // Nav list, driven by the Pages model + search filter.
        Column {
            id: navList
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.visiblePages
                delegate: SidebarItem {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    label: modelData.name
                    icon: modelData.icon
                    selected: index === root.currentIndex
                    onClicked: root.currentIndex = index
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
