pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * Laptop-battery state for the pill, sourced from UPower's display device and
 * gated so a desktop without a battery reports `present` false (the hover
 * cluster and 蓄 surface stay hidden). Exposes percentage, charge state, a
 * signed draw/charge wattage, capacity and optional health, plus a formatted
 * time-to-empty/full string. `low` flags a battery that is running down at or
 * below the `battLowPct` flag (20% shipped), and `plugged` tracks the AC line so
 * the OSD can flash on plug/unplug even at a charge threshold, where the device
 * state never reaches `Charging`.
 *
 * The charge state is read from the machine's own packs rather than only from
 * UPower's aggregate, so a two-pack laptop can say what each pack is doing and
 * PendingCharge — plugged in and held at a threshold — has a name. See `packs`,
 * `pending` and `packInfo`.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice

    readonly property bool present: dev !== null && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property real frac: dev ? Math.max(0, Math.min(1, dev.percentage)) : 0
    readonly property int pct: Math.round(frac * 100)
    readonly property int state: dev ? dev.state : UPowerDeviceState.Unknown

    /**
     * The machine's own packs, not the aggregate. `dev` above is UPower's
     * DisplayDevice — the one number UPower computes for the machine — but a
     * laptop with two packs (an internal and a removable one) has two states
     * behind that number, and the aggregate hides the one that matters: a pack
     * plugged in and held at a charge threshold while the other is full reads
     * from here as a single "Fully Charged". These are the packs, so the surface
     * can say what each is doing.
     */
    readonly property var packs: (typeof UPower !== "undefined" && UPower && UPower.devices)
        ? UPower.devices.values.filter(function(d) {
            return d && d.ready && d.isLaptopBattery === true && d.type === UPowerDeviceType.Battery;
        })
        : []

    readonly property bool anyCharging: packs.some(function(p) { return p.state === UPowerDeviceState.Charging; })
    readonly property bool anyPending: packs.some(function(p) { return p.state === UPowerDeviceState.PendingCharge; })
    readonly property bool allFull: packs.length > 0 && packs.every(function(p) {
        return p.state === UPowerDeviceState.FullyCharged || p.percentage >= 1;
    })

    /**
     * `charging` is the narrow fact — charge is going in right now. `pending` is
     * the one nothing used to name: PendingCharge is a pack the machine has
     * plugged in and is deliberately *not* charging, which on a ThinkPad is the
     * charge threshold doing its job. `onPower` is either of those plus full, and
     * is what the surfaces color from, so a held pack reads as plugged in rather
     * than as running down. `full` now means every pack, not the aggregate, or a
     * machine holding one pack at 80% would claim to be full.
     */
    readonly property bool charging: state === UPowerDeviceState.Charging || anyCharging
    readonly property bool pending: packs.length > 0 ? anyPending : state === UPowerDeviceState.PendingCharge
    readonly property bool full: packs.length > 0 ? allFull
        : (state === UPowerDeviceState.FullyCharged || pct >= 100)
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool onPower: plugged

    /**
     * Low is a warning about *running out*, so it is asked of a pack that is
     * actually running down: a battery plugged in and held at a threshold below
     * the warning mark is not something to warn about, and flashing at it is
     * what made an AC-connected machine look like it was about to die.
     */
    readonly property bool low: discharging && pct <= Flags.battLowPct

    /**
     * AC state, from UPower's line-power aggregate. `plugged` is what the
     * power-source OSD keys off: it flips the instant the cable goes in or out
     * even when the battery is at a charge threshold and never enters
     * `Charging` (a status the old charging-only flash missed entirely).
     */
    readonly property bool onBattery: UPower.onBattery
    readonly property bool plugged: present && !UPower.onBattery

    readonly property real rateW: !dev ? 0
        : (discharging ? -dev.changeRate : (charging ? dev.changeRate : 0))
    readonly property real capacityWh: dev ? dev.energyCapacity : 0

    readonly property bool healthSupported: dev ? dev.healthSupported : false
    readonly property int health: dev ? Math.round(dev.healthPercentage) : 0

    readonly property bool hasTime: !dev ? false
        : (charging ? dev.timeToFull > 0 : (discharging ? dev.timeToEmpty > 0 : false))
    readonly property string timeStr: !dev ? ""
        : (charging ? fmt(dev.timeToFull) : (discharging ? fmt(dev.timeToEmpty) : ""))

    readonly property string stateLabel: charging ? "Charging"
        : (pending ? "On AC · Holding"
        : (full ? "On AC · Full"
        : (discharging ? "Discharging" : "On AC")))

    /**
     * One pack per row, for the surface's stat list: its charge and what it is
     * doing, in the same words the state labels above use. Named by native path
     * (BAT0, BAT1 — what the pack is called everywhere else on the machine) with
     * the model as the fallback.
     */
    readonly property var packInfo: {
        var out = [];
        for (var i = 0; i < packs.length; i++) {
            var p = packs[i];
            var pctI = Math.round(Math.max(0, Math.min(1, p.percentage)) * 100);
            var path = String(p.nativePath || "");
            out.push({
                name: path.length ? path : ((p.model && p.model.length) ? p.model : "Pack"),
                value: pctI + "%" + packStateLabel(p.state)
            });
        }
        return out;
    }

    function packStateLabel(s) {
        switch (s) {
        case UPowerDeviceState.Charging: return " · charging";
        case UPowerDeviceState.PendingCharge: return " · holding";
        case UPowerDeviceState.FullyCharged: return " · full";
        case UPowerDeviceState.Discharging: return " · draining";
        case UPowerDeviceState.Empty: return " · empty";
        }
        return "";
    }

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return h + "h " + m + "m";
        return m + "m";
    }
}
