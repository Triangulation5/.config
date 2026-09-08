pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Services.Notifications
import qs.services
import qs.components.icons
import qs.components.controls
import qs.components.layout

/**
 * AOSP-style keyguard notification stack: collapsed per-app cards pinned below
 * the date, each showing the app icon, eyebrow, summary and a one-line body
 * preview. Tapping a card expands it to the full body and any action buttons;
 * hovering reveals a dismiss glyph. Only live notifications are shown — history
 * rows never appear on the lock. Critical entries carry the vermilion ember
 * and hairline, exactly like the inbox rows.
 */

Item {
    id: notifs

    property real s: 1.1

    /** Per-app expanded state, local to the lock so it never fights the inbox. */
    property var expandedApps: ({})

    /**
     * Live-only group cards. A group appears only while it still has tracked
     * (live) entries; the newest live entry drives the preview, and the count
     * sums just the live coalesced entries so history rows never inflate it.
     */
    readonly property var cards: {
        var out = [];
        for (var i = 0; i < Notifs.groups.length; i++) {
            var g = Notifs.groups[i];
            var live = g.criticals.concat(g.entries).filter(function(e) { return e.live; });
            if (live.length === 0)
                continue;
            var count = 0;
            for (var j = 0; j < live.length; j++)
                count += live[j].count || 1;
            /** Prefer a live critical for the preview (it carries the ember), else the newest live entry. */
            var preview = null;
            for (var k = 0; k < g.criticals.length && !preview; k++)
                if (g.criticals[k].live) preview = g.criticals[k].n;
            if (!preview)
                for (var m = 0; m < g.entries.length && !preview; m++)
                    if (g.entries[m].live) preview = g.entries[m].n;
            out.push({ app: g.app, n: preview, count: count });
        }
        return out;
    }

    /** Cap the visible stack so it never reaches the clock below. */
    readonly property int shown: Math.min(cards.length, 4)

    width: 320 * s
    implicitHeight: col.implicitHeight
    visible: cards.length > 0

    function toggleExpanded(app) {
        var e = Object.assign({}, notifs.expandedApps);
        e[app] = e[app] !== true;
        notifs.expandedApps = e;
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8 * s

        Repeater {
            model: notifs.shown

            delegate: NotifCard {
                width: col.width
                s: notifs.s
                app: notifs.cards[index].app
                n: notifs.cards[index].n
                count: notifs.cards[index].count
                expanded: notifs.expandedApps[notifs.cards[index].app] === true
            }
        }

        Item {
            visible: notifs.cards.length > notifs.shown
            width: parent.width
            height: 20 * s

            Text {
                anchors.centerIn: parent
                text: "+" + (notifs.cards.length - notifs.shown) + " more"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * s
                font.weight: Font.Bold
                font.letterSpacing: 1.2 * s
            }
        }
    }

    component NotifCard: Rectangle {
        id: card

        required property string app
        required property var n
        required property int count
        required property bool expanded
        property real s: 1.1

        readonly property bool critical: card.n.urgency === NotificationUrgency.Critical
        readonly property var acts: (card.n.actions || []).filter(function(a) { return a.text.length > 0; })

        radius: 14 * s
        border.width: 1
        border.color: Theme.border

        height: expanded ? Math.max(64 * s, bodyCol.implicitHeight + 26 * s) : 64 * s

        Behavior on height {
            NumberAnimation {
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowBlur: 0.9
            shadowVerticalOffset: 4 * s
        }

        CardFill {
            anchors.fill: parent
            radius: card.radius
        }

        /** Critical entries carry the vermilion left hairline, like the inbox. */
        Rectangle {
            visible: card.critical
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 2 * s
            width: 2.5 * s
            radius: 999
            color: Theme.verm
        }

        HoverHandler {
            id: hover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: notifs.toggleExpanded(card.app)
        }

        /** Each card lifts in as it appears, like notifications settling. */
        opacity: 0
        transform: Translate { id: lift; y: 8 * s }

        ParallelAnimation {
            id: intro
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        }

        Component.onCompleted: intro.start()

        Rectangle {
            id: tile
            anchors.left: parent.left
            anchors.leftMargin: 10 * s
            anchors.verticalCenter: parent.verticalCenter
            width: 30 * s
            height: 30 * s
            radius: 9 * s
            color: Theme.tileBg
            border.width: 1
            border.color: Theme.border

            Image {
                id: tileImg
                anchors.fill: parent
                anchors.margins: card.n.image ? 0 : 5 * s
                source: Notifs.iconFor(card.n)
                sourceSize.width: 48
                sourceSize.height: 48
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                visible: source.toString().length > 0
            }

            Rectangle {
                anchors.centerIn: parent
                visible: !tileImg.visible
                width: 6 * s
                height: 6 * s
                radius: 2 * s
                rotation: 45
                color: card.critical ? Theme.vermLit : Theme.verm
            }
        }

        Column {
            id: bodyCol
            anchors.left: tile.right
            anchors.leftMargin: 10 * s
            anchors.right: dismissRow.left
            anchors.rightMargin: 8 * s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * s

            Row {
                spacing: 5 * s

                /** Critical ember, matching the toast's pulse pair. */
                Item {
                    visible: card.critical
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8 * s
                    height: 8 * s

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8 * s
                        height: 8 * s
                        radius: 999
                        color: Theme.flameGlow
                        opacity: 0.3
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 4 * s
                        height: 4 * s
                        radius: 999
                        color: Theme.flameGlow
                    }
                }

                Text {
                    text: card.app.length ? card.app : "System"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 8.5 * s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.4 * s
                    elide: Text.ElideRight
                }

                Text {
                    visible: card.count > 1
                    text: "×" + card.count
                    color: Theme.vermDim
                    font.family: Theme.font
                    font.pixelSize: 9 * s
                    font.weight: Font.Bold
                }
            }

            Text {
                width: parent.width
                text: card.n.summary
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11.5 * s
                font.weight: Font.DemiBold
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: card.n.body
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * s
                wrapMode: Text.Wrap
                maximumLineCount: card.expanded ? 4 : 1
                elide: Text.ElideRight
                textFormat: Text.PlainText
                visible: card.n.body.length > 0
            }

            Row {
                visible: card.expanded && card.acts.length > 0
                spacing: 6 * s
                topPadding: 3 * s

                Repeater {
                    model: card.acts

                    Rectangle {
                        id: actPill
                        required property var modelData
                        height: 20 * s
                        width: actText.implicitWidth + 18 * s
                        radius: 999
                        color: Theme.tileBg
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: actPill.modelData.text
                            color: actPill.modelData.identifier === "default" ? Theme.vermLit : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 9.5 * s
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                actPill.modelData.invoke();
                                if (actPill.modelData.identifier === "default")
                                    Notifs.raiseWindow(card.n);
                                Notifs.dismissApp(card.app);
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: dismissRow
            anchors.right: parent.right
            anchors.rightMargin: 8 * s
            anchors.top: parent.top
            anchors.topMargin: 9 * s
            spacing: 8 * s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !hover.hovered
                text: Notifs.ageLabel(card.n)
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * s

                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.fast
                    }
                }
            }

            HoverIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: hover.hovered
                width: 11 * s
                height: 11 * s
                name: "close"
                color: Theme.dim
                hoverColor: Theme.cream
                stroke: 1.9
                hitPad: 6 * s
                enabled: hover.hovered
                onClicked: Notifs.dismissApp(card.app)
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 10 * s
                height: 10 * s
                name: card.expanded ? "chevron-down" : "chevron-right"
                color: Theme.faint
                stroke: 2
            }
        }
    }
}