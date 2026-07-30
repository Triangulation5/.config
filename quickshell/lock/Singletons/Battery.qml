pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * Central battery state provider sourced from UPower's display device.
 * Exposes normalized charge percentage, charging/discharging state, power
 * draw, capacity, health information, and estimated remaining/charging time.
 *
 * `present` is gated only by the existence and readiness of a valid UPower
 * device, allowing systems with inconsistent `isLaptopBattery` reporting to
 * still expose battery information. `low` marks a discharging battery at or
 * below 20%.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice

    readonly property bool present: dev !== null && dev.ready && dev.isPresent

    readonly property real frac: dev
        ? Math.max(0, Math.min(1, dev.percentage))
        : 0

    readonly property int pct: Math.round(frac * 100)

    readonly property int state: dev
        ? dev.state
        : UPowerDeviceState.Unknown

    readonly property bool charging:
        state === UPowerDeviceState.Charging

    readonly property bool full:
        state === UPowerDeviceState.FullyCharged || pct >= 100

    readonly property bool discharging:
        state === UPowerDeviceState.Discharging

    readonly property bool low:
        discharging && pct <= 20

    readonly property real rateW: !dev
        ? 0
        : (discharging
            ? -dev.changeRate
            : (charging ? dev.changeRate : 0))

    readonly property real capacityWh:
        dev ? dev.energyCapacity : 0

    readonly property bool healthSupported:
        dev ? dev.healthSupported : false

    readonly property int health:
        dev ? Math.round(dev.healthPercentage) : 0

    readonly property bool hasTime: !dev
        ? false
        : (charging
            ? dev.timeToFull > 0
            : (discharging ? dev.timeToEmpty > 0 : false))

    readonly property string timeStr: !dev
        ? ""
        : (charging
            ? fmt(dev.timeToFull)
            : (discharging ? fmt(dev.timeToEmpty) : ""))

    readonly property string stateLabel:
        charging ? "Charging"
        : (full ? "On AC · Full"
        : (discharging ? "Discharging" : "On AC"))

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);

        if (h > 0)
            return h + "h " + m + "m";

        return m + "m";
    }
}
