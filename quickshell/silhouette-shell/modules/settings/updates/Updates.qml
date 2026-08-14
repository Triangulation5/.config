pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.settings
import qs.modules.controlcenter
import qs.components.icons
import qs.components.controls

/**
 * 更 UPDATES sub-surface: renders the update state owned by the Updates
 * service. This surface is pure presentation — the check/apply engine, its
 * processes and every policy decision live in the singleton, so the state
 * survives surface churn and the pill can read `Updates.applying` for its
 * auth-pending gate. Reached from the settings index and morphs back to it on
 * an empty click or the back chevron.
 */
SettingsSurface {
    id: root

    backSurface: "settings"
    implicitHeight: content.implicitHeight
    rows: []

    /** rel-path -> human label for the protected files the engine can three-way merge. */
    readonly property var friendlyName: ({
        "hypr/modules/binds.lua": "Keybinds",
        "hypr/modules/decoration.lua": "Look",
        "hypr/modules/monitors.lua": "Display",
        "hypr/modules/input.lua": "Input",
        "hypr/modules/env.lua": "Environment",
        "hypr/modules/autostart.lua": "Autostart",
        "hypr/modules/animations.lua": "Animations",
        "hypr/hypridle.conf": "Idle & Lock"
    })

    function labelFor(rel) {
        return friendlyName[rel] !== undefined ? friendlyName[rel] : rel;
    }

    /** Title-case the package id into a readable label, e.g. noto-fonts-cjk -> Noto Fonts Cjk. */
    function prettyDep(id) {
        return id.split("-").map(function (w) {
            return w.length > 0 ? w.charAt(0).toUpperCase() + w.slice(1) : w;
        }).join(" ");
    }

    readonly property string badgeIcon: Updates.statusKind === "behind" ? "arrow-up"
        : Updates.statusKind === "error" || Updates.statusKind === "offline" ? "close"
        : Updates.statusKind === "devmode" ? "bolt"
        : Updates.statusKind === "noclone" ? "download"
        : "check"

    readonly property color badgeTint: Updates.statusKind === "error" || Updates.statusKind === "offline" ? Theme.dim
        : Updates.statusKind === "checking" || Updates.statusKind === "applying" || Updates.statusKind === "idle" || Updates.statusKind === "noclone" ? Theme.subtle
        : Theme.vermLit

    readonly property string headline: Updates.statusKind === "applying" ? "Updating…"
        : Updates.statusKind === "checking" ? "Checking…"
        : Updates.statusKind === "applied" ? "Updated"
        : Updates.statusKind === "devmode" ? "Developer install"
        : Updates.statusKind === "offline" ? "Couldn't reach the server"
        : Updates.statusKind === "noclone" ? "Ready to set up"
        : Updates.statusKind === "error" ? "Check failed"
        : Updates.statusKind === "behind" ? (Updates.behindCount + " update" + (Updates.behindCount === 1 ? "" : "s") + " available")
        : Updates.statusKind === "ok" ? "Up to date"
        : "Updates"

    /** A line beneath the headline that orients each state, dropped when empty. */
    readonly property string subline: Updates.statusKind === "devmode" ? "This is a clone or symlinked work-tree, so updates run through plain git. In-app updating is off here."
        : Updates.statusKind === "noclone" ? "The rice copy didn't land yet. Check for updates to fetch it, then updates show up here."
        : Updates.statusKind === "error" ? Updates.errorText
        : Updates.statusKind === "behind" ? (Updates.fromDate.length > 0 ? Updates.fromDate + " → " + Updates.toDate : "")
        : ""

    onActiveChanged: {
        if (active) {
            Updates.startCheck();
        } else {
            Updates.checking = false;
            Updates.applying = false;
            focusRowItem = null;
            kbIndex = -1;
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "更"
            title: "UPDATES"
            showBack: true
        }

        Item { width: 1; height: 14 * root.s }

        UpdateStatus {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            s: root.s
            badgeTint: root.badgeTint
            badgeIcon: root.badgeIcon
            headline: root.headline
            subline: root.subline
        }

        Item { width: 1; height: 15 * root.s }

        /**
         * The changelog is the centrepiece when an update waits: each entry is a
         * short row with a small marker, the list scrolls when it outgrows its
         * cap. Hidden in every other state so up-to-date and devmode stay calm.
         */
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            spacing: 8 * root.s
            visible: Updates.behind

            Text {
                text: "WHAT'S NEW"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.4 * root.s
            }

            Text {
                width: parent.width
                visible: Updates.changelog.length === 0
                text: "No highlights noted"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
                font.italic: true
            }

            ListView {
                id: logList
                width: parent.width
                height: visible ? Math.min(contentHeight, 168 * root.s) : 0
                visible: Updates.changelog.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Updates.changelog

                delegate: Row {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 9 * root.s
                    topPadding: 3 * root.s
                    bottomPadding: 3 * root.s

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 9 * root.s
                        width: 4 * root.s
                        height: 4 * root.s
                        radius: width / 2
                        color: Theme.vermLit
                    }

                    Text {
                        width: parent.width - 13 * root.s
                        text: parent.modelData
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11.5 * root.s
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                        lineHeight: 1.2
                    }
                }

                WheelScroller {
                    anchors.fill: parent
                    s: root.s
                    flick: logList
                }
            }
        }

        Item { width: 1; height: Updates.behind ? 14 * root.s : 0 }

        /**
         * Conflicts: every protected file whose local edits overlap an upstream
         * change. Each lists by friendly name with a two-way choice, "Keep mine"
         * the default and "Take new" overwriting wholesale on apply.
         */
        UpdateConflicts {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            s: root.s
            host: root
        }

        Item { width: 1; height: Updates.conflicts.length > 0 ? 14 * root.s : 0 }

        /**
         * Missing packages: core packages the rice needs that aren't installed yet,
         * whether this update introduced them or they were never there. Each is a row
         * with the package label, its one-line purpose, and a toggle that defaults ON,
         * so a plain "Update now" brings the rice and its packages over together. The
         * chosen ids ride along as --install-deps and the engine batches the repo ones
         * into a single pkexec install.
         */
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            spacing: 9 * root.s
            visible: Updates.behind && Updates.missingDeps.length > 0

            Text {
                width: parent.width
                text: "Needs " + Updates.missingDeps.length + " package" + (Updates.missingDeps.length === 1 ? "" : "s")
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: Updates.missingDeps

                Item {
                    id: depRow
                    required property var modelData
                    readonly property string depId: modelData.id

                    width: parent.width
                    height: depCol.implicitHeight + 12 * root.s

                    Column {
                        id: depCol
                        anchors.left: parent.left
                        anchors.right: depToggle.left
                        anchors.rightMargin: 12 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s

                        Text {
                            text: root.prettyDep(depRow.depId)
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            visible: depRow.modelData.desc.length > 0
                            text: depRow.modelData.desc
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                            lineHeight: 1.15
                        }
                    }

                    LinkToggle {
                        id: depToggle
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        s: root.s
                        on: Updates.depChosen(depRow.depId)
                        onToggled: Updates.installDeps = Object.assign({}, Updates.installDeps, { [depRow.depId]: !Updates.depChosen(depRow.depId) })
                    }
                }
            }
        }

        Item { width: 1; height: (Updates.behind && Updates.missingDeps.length > 0) ? 14 * root.s : 0 }

        /**
         * Install failures: any chosen package the last apply couldn't bring in. The
         * engine already folds the manual command into each reason for the deps it
         * can't drive headless (AUR, fallback-only), so a row is package plus the
         * exact why. Shown until the next check, independent of the behind state, so a
         * cancelled prompt or a build that needs a terminal never reads as success.
         */
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            spacing: 9 * root.s
            visible: Updates.depFailures.length > 0

            Text {
                width: parent.width
                text: "Couldn't install " + Updates.depFailures.length + " package" + (Updates.depFailures.length === 1 ? "" : "s")
                color: Theme.verm
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: Updates.depFailures

                Row {
                    id: failRow
                    required property var modelData
                    width: parent.width
                    spacing: 9 * root.s

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 6 * root.s
                        width: 4 * root.s
                        height: 4 * root.s
                        radius: width / 2
                        color: Theme.verm
                    }

                    Column {
                        width: parent.width - 13 * root.s
                        spacing: 2 * root.s

                        Text {
                            text: root.prettyDep(failRow.modelData.id)
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: failRow.modelData.error
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 10 * root.s
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                            lineHeight: 1.15
                        }
                    }
                }
            }
        }

        Item { width: 1; height: Updates.depFailures.length > 0 ? 14 * root.s : 0 }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            visible: Updates.behind || Updates.statusKind !== "devmode"
            height: visible ? 1 : 0
            color: Theme.hair
        }

        Item { width: 1; height: (Updates.behind || Updates.statusKind !== "devmode") ? 15 * root.s : 0 }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s
            spacing: 9 * root.s

            Rectangle {
                id: updateBtn
                width: parent.width
                height: 38 * root.s
                radius: 10 * root.s
                visible: Updates.behind
                color: Qt.alpha(Theme.vermLit, updateHover.hovered ? 0.30 : 0.20)
                border.width: 1
                border.color: Qt.alpha(Theme.vermLit, 0.55)
                opacity: Updates.applying ? 0.55 : 1
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                HoverHandler {
                    id: updateHover
                    enabled: !Updates.applying
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !Updates.applying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Updates.startApply()
                }

                Text {
                    anchors.centerIn: parent
                    text: Updates.applying ? "Updating…" : "Update now"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                id: checkBtn
                width: parent.width
                height: 38 * root.s
                radius: 10 * root.s
                visible: Updates.statusKind !== "devmode"
                color: checkHover.hovered ? Qt.alpha(Theme.onGlow, 0.34) : Qt.alpha(Theme.onGlow, 0.20)
                border.width: 1
                border.color: Qt.alpha(Theme.onGlow, checkHover.hovered ? 0.6 : 0.4)
                opacity: Updates.busy ? 0.55 : 1
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                HoverHandler {
                    id: checkHover
                    enabled: !Updates.busy
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !Updates.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Updates.startCheck()
                }

                Text {
                    anchors.centerIn: parent
                    text: Updates.checking ? "Checking…"
                        : Updates.statusKind === "offline" ? "Retry"
                        : "Check for updates"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    font.weight: Font.DemiBold
                }
            }

            Text {
                width: parent.width
                visible: Updates.restartNeeded && Updates.depFailures.length === 0
                text: "Updated · restarting the shell"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.2
            }
        }
    }
}
