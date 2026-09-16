import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.settingsapp.config
import qs.modules.settingsapp.pages
import qs.modules.settingsapp.modules.sidebar

/**
 * The rail: a search field over a scrolling page list. It owns the selection
 * (`currentIndex`), which the host binds the content area to, and knows nothing
 * about what a page contains — its model is `Pages.navEntries(query)`.
 *
 * Two kinds of row come out of that model: a page, and — while a query is live —
 * each of that page's settings that matched, indented under it. A page row says
 * "open this page"; a hit says "open this page *and show me this setting*", which
 * it reports as `rowRequested` rather than moving anything, exactly as the
 * content area's chevrons report a step: the selection is this rail's property,
 * and a row that assigned to it directly would be a second writer.
 *
 * The rows land directly in this ColumnLayout. Inside a plain Column the
 * `Layout.fillWidth` on each row would be ignored and every row would collapse
 * to zero width, which is how an empty rail happens.
 *
 * The list is a scroll view because the rail no longer fits on the window: at
 * twelve pages the last few were simply unreachable, and every page added from
 * here would have made that worse. The search field stays fixed above it, since
 * scrolling the field you are typing into away from the cursor is its own kind
 * of broken.
 *
 * Above both sits the app's own mark: the icon this window wears in a launcher
 * (`assets/silhouette-settings.svg`, the same file the desktop entry points at),
 * drawn from the asset rather than baked in like the pill's glyphs, because an
 * app icon is a file other programs have to be able to read. It is the only
 * thing in the rail that is the app rather than a page.
 */
Rectangle {
    id: root

    property int currentIndex: 0

    /** The live search query, following the field below. */
    property string query: search.text

    /** A rail row asking for the page at `pageIndex`, scrolled to `rowKey`. */
    signal pageSelected(int pageIndex)
    signal rowRequested(int pageIndex, string rowKey)

    readonly property var entries: Pages.navEntries(query)

    color: Theme.sidebar

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        spacing: 6

        RowLayout {
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.fillWidth: true
            spacing: 9

            Image {
                Layout.alignment: Qt.AlignVCenter
                source: Qt.resolvedUrl("../../assets/silhouette-settings.svg")
                sourceSize.width: 22
                sourceSize.height: 22
                smooth: true
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: "Silhouette Settings"
                color: Theme.text
                font.pixelSize: Theme.fontSizeNormal
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Item { Layout.preferredHeight: 4 }

        SidebarSearch {
            id: search
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 8 }

        ScrollView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            // No bar and no trough: the default Qt scrollbar is a light grey slab
            // that has nothing to do with this panel, and it is drawn as an
            // overlay *on* the rows. The list still scrolls — wheel, trackpad,
            // and a drag that started over it — and a cut-off row is the hint
            // that there is more below.
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                // The viewport's own width: a layout inside a scroll view is
                // handed its implicit width, which would leave the rows as wide
                // as their longest label and the highlight short of the edge.
                width: list.availableWidth
                spacing: 2

                Repeater {
                    model: root.entries

                    delegate: ColumnLayout {
                        id: entry

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 0

                        SidebarItem {
                            Layout.fillWidth: true
                            label: entry.modelData.page.name
                            icon: entry.modelData.page.icon
                            // modelData.index is the page's real position in
                            // the index, so a filtered rail still opens the page
                            // it shows rather than the row's position in the
                            // filter.
                            selected: entry.modelData.index === root.currentIndex
                            onClicked: root.pageSelected(entry.modelData.index)
                        }

                        Repeater {
                            model: entry.modelData.hits

                            delegate: SidebarHit {
                                id: hit

                                required property var modelData

                                Layout.fillWidth: true
                                label: hit.modelData.label
                                onClicked: root.rowRequested(entry.modelData.index, Pages.rowKey(hit.modelData))
                            }
                        }
                    }
                }

                // Nothing matched the query: say so instead of leaving a silent
                // gap where the nav list used to be.
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    visible: root.entries.length === 0
                    text: "No settings match \u201C" + root.query.trim() + "\u201D"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    // Divider between the rail and the content area.
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }
}
