import QtQuick
import QtQuick.Layouts
import qs.modules.settingsapp.config
import qs.modules.settingsapp.services
import qs.modules.settingsapp.components

/**
 * The Updates page body: what the updater found, and the one button that installs
 * it.
 *
 * The check runs when the page opens rather than on a timer: `dnf check-update`
 * hits the network, and a settings window that calls it every few minutes in the
 * background is a settings window that owns a mirror refresh the user never asked
 * for. Opening the page *is* the ask.
 *
 * Install is behind a confirm step because it is the only control in this app that
 * escalates through pkexec, and the only one that changes the machine rather than
 * a config file. Everything the script does is on the same contract (see the
 * Updates service), so the page offers exactly what it implements: a check, and an
 * upgrade — the whole set or the minimal one.
 */
ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: 22

    /** True while the install waits for a second click. */
    property bool confirming: false

    /** At most this many package names are drawn; the rest are counted. */
    readonly property int listed: 40

    Component.onCompleted: Updates.check()

    /** The page's headline: what state the updater is in, in a few words. */
    readonly property string headline: Updates.statusKind === "applying" ? "Updating\u2026"
        : Updates.statusKind === "checking" ? "Checking\u2026"
        : Updates.statusKind === "error" ? "Couldn't check for updates"
        : Updates.statusKind === "behind" ? (Updates.pending + " update" + (Updates.pending === 1 ? "" : "s") + " available")
        : Updates.statusKind === "ok" ? "Up to date"
        : "Updates"

    /** The line under it, orienting that state. "" drops the line. */
    readonly property string subline: Updates.statusKind === "error" ? Updates.errorText
        : Updates.statusKind === "behind" ? "Installing runs the config's updater, which escalates for the upgrade itself."
        : Updates.statusKind === "ok" ? "Nothing to install."
        : Updates.statusKind === "checking" ? "Asking the package manager."
        : Updates.statusKind === "applying" ? "This can take a while, and asks for your password."
        : ""

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
                    color: Updates.statusKind === "error" ? Theme.textSecondary
                        : Updates.statusKind === "behind" ? Theme.accent
                        : Theme.textSecondary
                    opacity: Updates.busy ? 0.5 : 1

                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.headline
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeNormal
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                // Check: available in every settled state, disabled while busy.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: checkLabel.implicitWidth + 24
                    implicitHeight: 30
                    radius: 8
                    opacity: Updates.busy ? 0.5 : 1
                    color: checkMouse.containsMouse && !Updates.busy ? Theme.hover : Theme.navButton
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        id: checkLabel
                        anchors.centerIn: parent
                        text: Updates.busy ? "Working\u2026" : "Check again"
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSection
                        font.bold: true
                    }

                    MouseArea {
                        id: checkMouse
                        anchors.fill: parent
                        enabled: !Updates.busy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Updates.check()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.subline.length > 0
                text: root.subline
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
            }

            // The install affordance lives here, so it is never on screen when
            // there is nothing to install.
            ColumnLayout {
                Layout.fillWidth: true
                visible: Updates.behind
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [{ label: "All packages", minimal: false },
                                { label: "Security & fixes", minimal: true }]

                        delegate: Rectangle {
                            id: mode

                            required property var modelData

                            implicitWidth: modeLabel.implicitWidth + 22
                            implicitHeight: 28
                            radius: 8
                            color: Updates.securityOnly === mode.modelData.minimal ? Qt.alpha(Theme.accent, 0.22) : Theme.searchField
                            border.width: 1
                            border.color: Updates.securityOnly === mode.modelData.minimal ? Qt.alpha(Theme.accent, 0.5) : Theme.border

                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                            Text {
                                id: modeLabel
                                anchors.centerIn: parent
                                text: mode.modelData.label
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSection
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Updates.securityOnly = mode.modelData.minimal
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        implicitWidth: updateLabel.implicitWidth + 28
                        implicitHeight: 32
                        radius: 8
                        opacity: Updates.busy ? 0.5 : 1
                        color: updateMouse.containsMouse && !Updates.busy
                            ? Theme.accent : Qt.alpha(Theme.accent, 0.85)

                        Text {
                            id: updateLabel
                            anchors.centerIn: parent
                            text: root.confirming ? "Yes, install" : "Update now"
                            color: Theme.knob
                            font.pixelSize: Theme.fontSizeNormal
                            font.bold: true
                        }

                        MouseArea {
                            id: updateMouse
                            anchors.fill: parent
                            enabled: !Updates.busy
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.confirming) {
                                    root.confirming = true;
                                    return;
                                }
                                root.confirming = false;
                                Updates.apply();
                            }
                        }
                    }

                    Rectangle {
                        visible: root.confirming
                        implicitWidth: cancelLabel.implicitWidth + 24
                        implicitHeight: 32
                        radius: 8
                        color: cancelMouse.containsMouse ? Theme.hover : "transparent"
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            id: cancelLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeNormal
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirming = false
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.confirming
                        text: "This installs " + Updates.pending + " package"
                            + (Updates.pending === 1 ? "" : "s") + " on your machine."
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSection
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    // The pending packages: what "42 updates" is made of.
    Rectangle {
        Layout.fillWidth: true
        visible: Updates.packages.length > 0
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: packageColumn.implicitHeight + 36

        ColumnLayout {
            id: packageColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            SectionLabel {
                Layout.fillWidth: true
                text: "Pending"
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: Updates.packages.slice(0, root.listed)

                    delegate: Rectangle {
                        id: pkg

                        required property var modelData

                        implicitWidth: pkgLabel.implicitWidth + 18
                        implicitHeight: 24
                        radius: 7
                        color: Theme.searchField
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            id: pkgLabel
                            anchors.centerIn: parent
                            text: pkg.modelData
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSection
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: Updates.packages.length > root.listed
                text: "and " + (Updates.packages.length - root.listed) + " more"
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
            }
        }
    }

    // What the last install did, per command the script ran.
    Rectangle {
        Layout.fillWidth: true
        visible: Updates.results.length > 0
        color: Theme.card
        radius: Theme.radiusCard
        implicitHeight: resultColumn.implicitHeight + 36

        ColumnLayout {
            id: resultColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            SectionLabel {
                Layout.fillWidth: true
                text: Updates.applied ? "Installed" : "Last run"
            }

            Repeater {
                model: Updates.results

                delegate: ColumnLayout {
                    id: result

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: (result.modelData.success ? "\u2713  " : "\u00D7  ") + result.modelData.command
                        color: result.modelData.success ? Theme.text : Theme.accent
                        font.pixelSize: Theme.fontSizeSection
                        wrapMode: Text.WordWrap
                    }

                    // Only a failure's tail is worth showing: the last lines are
                    // where a package manager says what it refused and why.
                    Text {
                        Layout.fillWidth: true
                        visible: !result.modelData.success
                        text: root.tail(result.modelData.output)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSection
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: Updates.rebootNeeded
                text: "A reboot is recommended to finish replacing libraries that are in use."
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSection
                wrapMode: Text.WordWrap
            }
        }
    }

    /** The last few lines of a command's output — the part that explains it. */
    function tail(output) {
        var lines = String(output).replace(/\s+$/, "").split("\n");
        return lines.slice(Math.max(0, lines.length - 6)).join("\n");
    }
}
