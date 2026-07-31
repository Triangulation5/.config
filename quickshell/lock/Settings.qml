pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

/**
 * Lockscreen Settings View featuring fixed header and scrollable Flickable category rows.
 */
SettingsSurface {
    id: root

    property bool confirmReboot: false
    property bool confirmShutdown: false

    onOpenChanged: {
        if (!open) {
            confirmReboot = false;
            confirmShutdown = false;
        }
    }

    SettingsHeader {
        id: fixedHeader
        s: root.s
        title: "SETTINGS"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
    }

    Flickable {
        id: flick
        anchors.top: fixedHeader.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        contentHeight: mainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: mainCol
            width: flick.width
            spacing: 4 * root.s

            // --- APPEARANCE ---
            SettingsCategory {
                s: root.s
                title: "Appearance"
            }

            SettingsRow {
                s: root.s
                icon: "waves"
                name: "Music Visualizer"
                sub: "Show reactive audio visualizer"

                SettingsToggle {
                    s: root.s
                    checked: Flags.visualizerEnabled
                    onToggled: val => {
                        Flags.visualizerEnabled = val;
                        Cava.enabled = val;
                        Flags.save();
                    }
                }
            }

            // --- TIME & DATE ---
            SettingsCategory {
                s: root.s
                title: "Time & Date"
            }

            SettingsRow {
                s: root.s
                icon: "clock"
                name: "Show Seconds"
                sub: "Display seconds on clock"

                SettingsToggle {
                    s: root.s
                    checked: Flags.showSeconds
                    onToggled: val => {
                        Flags.showSeconds = val;
                        Flags.save();
                    }
                }
            }

            SettingsRow {
                s: root.s
                icon: "clock"
                name: "Date Format"
                sub: "Select lockscreen date style"

                SettingsSelector {
                    s: root.s
                    value: Flags.dateFormat
                    options: ["Monday, July 30", "Jul 30, 2026", "30/07/2026", "2026-07-30"]
                    onSelected: val => {
                        Flags.dateFormat = val;
                        Flags.save();
                    }
                }
            }

            // --- DISPLAY ---
            SettingsCategory {
                s: root.s
                title: "Display"
            }

            SettingsRow {
                s: root.s
                icon: "monitor"
                name: "Brightness"
                sub: Math.round(Backlight.brightness * 100) + "%"

                SettingsSlider {
                    s: root.s
                    value: Backlight.brightness
                    onValueMoved: val => {
                        Backlight.setBrightness(val);
                        Flags.brightness = val;
                        Flags.save();
                    }
                }
            }

            SettingsRow {
                s: root.s
                icon: "eye"
                name: "Night Light"
                sub: "Warm screen color filter"

                SettingsToggle {
                    s: root.s
                    checked: NightLight.enabled
                    onToggled: val => {
                        NightLight.setEnabled(val);
                        Flags.nightLight = val;
                        Flags.save();
                    }
                }
            }

            // --- NETWORK ---
            SettingsCategory {
                s: root.s
                title: "Network"
            }

            SettingsRow {
                s: root.s
                icon: "wifi"
                name: "Wi-Fi"
                sub: Network.wifiEnabled ? Network.currentNetwork : "Disabled"

                SettingsToggle {
                    s: root.s
                    checked: Network.wifiEnabled
                    onToggled: val => {
                        Network.setWifiEnabled(val);
                        Flags.wifiEnabled = val;
                        Flags.save();
                    }
                }
            }

            SettingsRow {
                s: root.s
                icon: "waves"
                name: "Bluetooth"
                sub: Bluetooth.bluetoothActive ? "Connected" : "Off"

                SettingsToggle {
                    s: root.s
                    checked: Bluetooth.bluetoothActive
                    onToggled: val => {
                        Bluetooth.setBluetooth(val);
                        Flags.bluetoothActive = val;
                        Flags.save();
                    }
                }
            }

            // --- SYSTEM ---
            SettingsCategory {
                s: root.s
                title: "System"
            }

            SettingsRow {
                s: root.s
                icon: "lock"
                name: "Suspend"
                sub: "Put system to sleep"

                onClicked: System.suspend()

                GlyphIcon {
                    width: 14 * root.s
                    height: 14 * root.s
                    name: "chevron-right"
                    color: Theme.iconDim
                }
            }

            SettingsRow {
                s: root.s
                icon: "return"
                name: root.confirmReboot ? "Confirm Restart?" : "Restart"
                sub: root.confirmReboot ? "Tap again to reboot system" : "Reboot the system"

                onClicked: {
                    if (root.confirmReboot) {
                        System.reboot();
                    } else {
                        root.confirmReboot = true;
                        root.confirmShutdown = false;
                    }
                }

                GlyphIcon {
                    width: 14 * root.s
                    height: 14 * root.s
                    name: "chevron-right"
                    color: root.confirmReboot ? Theme.verm : Theme.iconDim
                }
            }

            SettingsRow {
                s: root.s
                icon: "shutdown"
                name: root.confirmShutdown ? "Confirm Shutdown?" : "Shutdown"
                sub: root.confirmShutdown ? "Tap again to power off" : "Power off system"
                last: true

                onClicked: {
                    if (root.confirmShutdown) {
                        System.shutdown();
                    } else {
                        root.confirmShutdown = true;
                        root.confirmReboot = false;
                    }
                }

                GlyphIcon {
                    width: 14 * root.s
                    height: 14 * root.s
                    name: "chevron-right"
                    color: root.confirmShutdown ? Theme.verm : Theme.iconDim
                }
            }
        }
    }
}
