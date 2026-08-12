pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.launcher
import qs.components.animation
import qs.components.controls
import qs.modules.pill.surfaces
import qs.components.icons

/**
 * 控 CLIPBOARD — searchable cliphist history. The SearchField doubles as the
 * header with its kanji, placeholder and live count. Beneath a hairline a
 * ListView shows text and image entries; hovering rows cross-fades a dismiss
 * × glyph (Ctrl+X deletes the keyboard selection), Return copies and closes.
 * The 掃 wipe button at the header's right edge wipes the whole history after
 * a held confirmation sweep, whose progress draws along the divider. Empty
 * state centres a ghost 控 glyph with a status line.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 17
    mRight: 17
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0

    /** Last hover event's window position; used to suppress selection steal. */
    property point lastPointer: Qt.point(-1, -1)

    /** Ame soul docked at the search field's caret. */
    readonly property point caretPoint: {
        void root.width;
        void root.height;
        void search.input.width;
        return search.input.mapToItem(root,
            search.input.cursorRectangle.x + search.input.cursorRectangle.width / 2,
            search.input.cursorRectangle.y + search.input.cursorRectangle.height / 2);
    }

    ameForm: "caret"
    amePoint: Qt.point(caretPoint.x, caretPoint.y)

    implicitHeight: content.implicitHeight

    readonly property var results: {
        var all = Cliphist.entries;
        var q = query.trim().toLowerCase();
        if (!q.length) return all;
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var hay = (all[i].isImage ? all[i].label + " " + all[i].sizeLabel : all[i].preview).toLowerCase();
            if (hay.indexOf(q) !== -1) out.push(all[i]);
        }
        return out;
    }

    function focusField() { search.input.forceActiveFocus(); }

    function move(delta) {
        if (results.length === 0) return;
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activate() {
        if (results.length === 0 || selectedIndex < 0 || selectedIndex >= results.length) return;
        Cliphist.copy(results[selectedIndex]);
        root.requestClose();
    }

    function removeAt(index) {
        if (index < 0 || index >= results.length) return;
        Cliphist.remove(results[index]);
    }

    onActiveChanged: {
        if (active) {
            query = "";
            search.text = "";
            selectedIndex = 0;
            Cliphist.refresh();
            Qt.callLater(root.focusField);
        }
    }
    onResultsChanged: if (selectedIndex >= results.length) selectedIndex = Math.max(0, results.length - 1)

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SearchField {
            id: search
            z: 5
            width: parent.width
            s: root.s
            kanji: "控"
            placeholder: "Search clipboard"
            counterText: root.results.length + " / " + Cliphist.count
            onTextChanged: {
                root.query = text;
                root.selectedIndex = 0;
            }
            onMoved: (d) => root.move(d)
            onAccepted: root.activate()
            onDismissed: root.requestClose()
            onKeyPressed: (e) => {
                if (e.key === Qt.Key_X && (e.modifiers & Qt.ControlModifier)
                    && search.input.selectedText.length === 0) {
                    root.removeAt(root.selectedIndex);
                    e.accepted = true;
                }
            }

            /** Wipe button — hold 掃 to clear history, with sweep on divider. */
            Item {
                id: wipeBtn
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s

                readonly property real hold: wipeHeat.hold
                readonly property bool holding: wipeHeat.holding
                readonly property color tone: holding ? Theme.vermLit : (wipeArea.containsMouse ? Theme.cream : Theme.faint)

                Tooltip {
                    s: root.s
                    placement: "below"
                    title: "hold to wipe"
                    show: wipeArea.containsMouse || wipeBtn.holding
                }

                Text {
                    visible: Flags.showGlyphs
                    anchors.centerIn: parent
                    text: "掃"
                    color: wipeBtn.tone
                    font.family: Theme.fontJp
                    font.pixelSize: 12 * root.s
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                GlyphIcon {
                    visible: !Flags.showGlyphs
                    anchors.centerIn: parent
                    width: 12 * root.s; height: 12 * root.s
                    name: "trash"
                    color: wipeBtn.tone
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                HeatHold {
                    id: wipeHeat
                    onConfirmed: Cliphist.wipe()
                }

                MouseArea {
                    id: wipeArea
                    anchors.fill: parent
                    anchors.margins: -5 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: wipeHeat.press()
                    onReleased: wipeHeat.release()
                    onExited: wipeHeat.cancel()
                }
            }
        }

        Item { width: 1; height: 8 * root.s }

        /* ── Divider — wipe-progress sweep runs along it ── */
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: parent.width * wipeBtn.hold
                visible: wipeBtn.holding
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.vermLit, 0.15) }
                    GradientStop { position: 1.0; color: Theme.vermLit }
                }
            }
        }

        Item { width: 1; height: 6 * root.s }

        /* ── Empty state — ghost glyph + message ── */
        Item {
            width: parent.width
            height: (root.results.length === 0 && !Cliphist.count) ? 120 * root.s : 0
            visible: height > 0

            Column {
                anchors.centerIn: parent
                spacing: 12 * root.s

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Flags.showGlyphs
                    text: "控"
                    color: Theme.ghost
                    opacity: 0.18
                    font.family: Theme.fontJp
                    font.weight: Font.Bold
                    font.pixelSize: 48 * root.s
                }

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !Flags.showGlyphs
                    width: 32 * root.s; height: 32 * root.s
                    name: "clipboard"
                    color: Theme.ghost
                    stroke: 1.6
                    opacity: 0.2
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "History empty"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    font.weight: Font.Medium
                }
            }
        }

        /* ── No matches state ── */
        Text {
            width: parent.width
            visible: root.results.length === 0 && Cliphist.count > 0
            height: visible ? implicitHeight + 24 * root.s : 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "No matches"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
        }

        /* ── Results list ── */
        ListView {
            id: list
            width: parent.width
            height: count > 0 ? Math.min(count * 36 * root.s + (count - 1) * 2 * root.s, 300 * root.s) : 0
            visible: height > 0
            spacing: 2 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.results.length
            interactive: count * 36 * root.s > 300 * root.s

            delegate: Item {
                id: row
                required property int index
                width: list.width
                height: (entry && entry.isImage ? 44 : 28) * root.s

                readonly property var entry: root.results[index]
                readonly property bool selected: index === root.selectedIndex

                HoverHandler {
                    id: rowHover
                    onPointChanged: {
                        if (!hovered) return;
                        var sp = point.scenePosition;
                        if (sp.x !== root.lastPointer.x || sp.y !== root.lastPointer.y) {
                            root.lastPointer = Qt.point(sp.x, sp.y);
                            root.selectedIndex = row.index;
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 9 * root.s
                    visible: row.selected || rowHover.hovered
                    color: row.selected ? Theme.frameBg : Qt.rgba(0.94, 0.88, 0.84, 0.03)
                    border.width: row.selected ? 1 : 0
                    border.color: Theme.frameBorder
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedIndex = row.index;
                        root.activate();
                    }
                }

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 11 * root.s
                    anchors.rightMargin: 11 * root.s

                    /** Image thumbnail tile. */
                    Rectangle {
                        id: thumbTile
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.entry !== undefined && row.entry.isImage
                        width: visible ? 52 * root.s : 0
                        height: 32 * root.s
                        radius: 6 * root.s
                        color: Theme.tileBg
                        border.width: 1
                        border.color: Theme.border
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: thumbTile.visible ? "file://" + row.entry.thumb : ""
                            sourceSize.width: 128; sourceSize.height: 128
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                        }
                    }

                    /** Entry text — preview string or image label. */
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: thumbTile.visible ? thumbTile.right : parent.left
                        anchors.leftMargin: thumbTile.visible ? 9 * root.s : 0
                        anchors.right: sizeTag.left
                        anchors.rightMargin: 8 * root.s
                        text: row.entry === undefined ? "" : (row.entry.isImage ? row.entry.label : row.entry.preview)
                        color: row.entry !== undefined && row.entry.isImage
                            ? (row.selected ? Theme.dim : Theme.faint)
                            : (row.selected ? Theme.cream : Theme.subtle)
                        font.family: Theme.font
                        font.pixelSize: 11.5 * root.s
                        font.weight: row.selected ? Font.DemiBold : Font.Medium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    /** Size badge for images. */
                    Text {
                        id: sizeTag
                        anchors.right: tail.left
                        anchors.rightMargin: width > 0 ? 8 * root.s : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.entry !== undefined && row.entry.isImage ? row.entry.sizeLabel : ""
                        width: text.length ? implicitWidth : 0
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 10.5 * root.s
                        font.features: { "tnum": 1 }
                    }

                    /** Right tail — Return arrow or dismiss ×. */
                    Item {
                        id: tail
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(ret.implicitWidth, dismiss.implicitWidth)
                        height: Math.max(ret.implicitHeight, dismiss.implicitHeight)

                        Text {
                            id: ret
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: row.selected && !rowHover.hovered ? 1 : 0
                            text: "↵"
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 12 * root.s
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        }

                        Text {
                            id: dismiss
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: rowHover.hovered ? 1 : 0
                            text: "✕"
                            color: dismissArea.containsMouse ? Theme.cream : Theme.dim
                            font.pixelSize: 10 * root.s
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            MouseArea {
                                id: dismissArea
                                anchors.fill: parent
                                anchors.margins: -6 * root.s
                                enabled: rowHover.hovered
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeAt(row.index)
                            }
                        }
                    }
                }
            }
        }

        WheelScroller {
            anchors.fill: list
            s: root.s
            flick: list
        }
    }
}
