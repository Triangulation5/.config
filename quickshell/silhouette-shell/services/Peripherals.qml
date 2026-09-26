pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower

/**
 * The peripheral model: one row per attached device, carrying the four things a
 * row has to say about it — what it is, whether it is connected, how much charge
 * it has, and whether it is on power. The control center's Bluetooth drill-in and
 * the link row read this and nothing else, so one device cannot be described two
 * ways in two places, which is what "No battery reading" on one row and a battery
 * thread on another for the same headset used to be.
 *
 * Two sources feed it, and neither is enough alone:
 *
 *   BlueZ (Bluetooth.devices) is the authority on identity and connection:
 *   address, paired/connected/state, and — the part the UI used to throw away —
 *   `icon`, the freedesktop device class ("audio-headset", "input-gaming",
 *   "input-mouse"). That class is what a row's glyph should come from; without
 *   it every Bluetooth device is drawn as a generic Bluetooth mark, which is how
 *   a gamepad and a pair of headphones came out identical. BlueZ's own battery
 *   reading is published only with its Experimental Battery1 interface on, so it
 *   is a fallback here, not the source.
 *
 *   UPower is the authority on charge: percentage, rate, and the charge state —
 *   including PendingCharge, a pack the machine has plugged in but stopped
 *   charging at a threshold, which is neither "charging" nor "full" and which
 *   nothing in the UI used to name.
 *
 * Rows are keyed by MAC, normalized from whichever form each source has, so a
 * device both sources describe is one row. That is the duplicate this replaces:
 * a connected headset whose UPower entry did not match the BlueZ address by
 * string comparison was listed twice — once as a Bluetooth row with no battery
 * and once as a battery-only row — and a peripheral whose UPower *type* UPower
 * could not name was dropped entirely (see `upPeripherals`).
 *
 * `lowAt` (the `battLowPct` flag, 20% shipped) is shared with the laptop's own
 * warning so the two thresholds cannot drift. A peripheral at or below it while
 * *not* on power raises one notify-send, reset once it climbs back, goes on
 * power, or disappears.
 */
Singleton {
    id: root

    readonly property int lowAt: Flags.battLowPct

    /**
     * Re-evaluation counter for the model below. The row builders read device
     * properties across two object models, and a plain binding on either list
     * only re-evaluates when the *list* changes — a per-device `connected` or
     * `percentage` flip does not disturb it. The Instantiators at the bottom
     * hold a Connections on every device in both models and bump this, which is
     * the one dependency the model needs.
     */
    property int revision: 0

    function bump(): void {
        revision++;
    }

    readonly property var upDevices: (typeof UPower !== "undefined" && UPower && UPower.devices)
        ? UPower.devices.values : []
    readonly property var btDevices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices)
        ? Bluetooth.devices.values : []
    readonly property var btConnected: btDevices.filter(function(d) { return d && d.connected === true; })

    /**
     * UPower devices that are a peripheral rather than the machine's own power.
     *
     * `isLaptopBattery` is exactly `type == Battery && powerSupply`, so
     * excluding it drops the machine's own packs — both of them, on a
     * dual-battery laptop like this one — and nothing else. Line power is
     * excluded by type: the AC adapter and each USB-C port UPower publishes are
     * power *sources*, not devices.
     *
     * Everything left is a peripheral. Note what is deliberately *not* asked
     * here: the type. A peripheral's pack is type `Battery` too (it is a
     * battery), so the old `type !== Battery` clause excluded every peripheral
     * battery in existence — the list this service exists to build was always
     * empty, and every row fell back to "No battery reading". Nor is `Unknown`
     * excluded: a device UPower could not classify, that does not power the
     * machine, is a peripheral by elimination, and its kind is recovered from
     * BlueZ's icon class instead (see `kindOf`).
     *
     * `isPresent` is only meaningful for Battery-type devices (per the UPower
     * docs), so it is asked about those and ignored for the rest — a mouse
     * would read as absent otherwise.
     */
    readonly property var upPeripherals: upDevices.filter(isPeripheral)

    function isPeripheral(d) {
        if (!d || !d.ready || d.isLaptopBattery)
            return false;
        if (d.type === UPowerDeviceType.LinePower)
            return false;
        if (d.type === UPowerDeviceType.Battery && d.isPresent !== true)
            return false;
        return true;
    }

    /** ---- identity ---- */

    /**
     * One MAC in one shape: uppercase, colon-separated, or "" when the input has
     * no address in it. Both sources are put through this before anything is
     * compared, so `E8:A0:CD:82:B7:79` and `e8_a0_cd_82_b7_79` are the same
     * device and a row cannot be built twice for it.
     */
    function normMac(s) {
        var hex = String(s || "").toUpperCase().replace(/[^0-9A-F]/g, "");
        if (hex.length !== 12)
            return "";
        return hex.substr(0, 2) + ":" + hex.substr(2, 2) + ":" + hex.substr(4, 2) + ":"
            + hex.substr(6, 2) + ":" + hex.substr(8, 2) + ":" + hex.substr(10, 2);
    }

    /**
     * The MAC a UPower peripheral carries in its native path, or "" for a dongle.
     *
     * UPower names a Bluetooth device's supply after the device, so the address
     * is in there — with separators (`E8_A0_CD_82_B7_79`, BlueZ's `E8:A0:...`),
     * which is what this laptop's Bluetooth supplies use — or as one bare run of
     * hex. Only those two shapes are read, and the bare run is only read when it
     * is the whole last path element: a USB path is full of four-digit hex
     * segments (`pci0000:00`, `0000:00:14.0`), and reading one of those as an
     * address would give two unrelated dongles the same key and merge them into
     * one row. A path in some third shape simply yields no MAC, which costs the
     * Bluetooth↔UPower join and nothing else: the peripheral still gets its own
     * row, just not the BlueZ half of it.
     */
    function macOf(d) {
        var p = String((d && d.nativePath) || "");
        var m = p.match(/(?:[0-9A-Fa-f]{2}[:_]){5}[0-9A-Fa-f]{2}/);
        if (m)
            return normMac(m[0]);
        var base = p.substr(p.lastIndexOf("/") + 1);
        return /^[0-9A-Fa-f]{12}$/.test(base) ? normMac(base) : "";
    }

    /** ---- charge ---- */

    /**
     * Percentage, 0-100, or -1 when there is no reading to give.
     *
     * `percentage` is documented as `energy / energyCapacity`, and is what
     * UPower normally publishes; where it comes back empty the two numbers are
     * used directly. `-1` rather than `0` is the point: "no reading" and "empty"
     * are different things and the rows say different words for them.
     */
    function pct(d) {
        if (!d)
            return -1;
        var p = Number(d.percentage);
        if (!isFinite(p) || p <= 0)
            p = (Number(d.energyCapacity) > 0) ? Number(d.energy) / Number(d.energyCapacity) : NaN;
        if (!isFinite(p))
            return -1;
        return Math.round(Math.max(0, Math.min(1, p)) * 100);
    }

    /** UPower's reading first, BlueZ's as the fallback; -1 when neither has one. */
    function levelOf(up, bt) {
        var p = up ? pct(up) : -1;
        if (p >= 0)
            return p;
        if (bt && bt.batteryAvailable === true)
            return Math.round(Math.max(0, Math.min(1, bt.battery)) * 100);
        return -1;
    }

    /**
     * Whether the peripheral is drawing from something. `charging` is the
     * narrower fact — it is taking charge right now — and `onPower` is the one
     * the bolt shows: a peripheral on a dock at its charge limit
     * (PendingCharge) or already full (FullyCharged) is plugged in, and drawing
     * it as "not charging" is what left the row with no power indication at all.
     */
    function onPowerOf(d) {
        if (!d)
            return false;
        return d.state === UPowerDeviceState.Charging
            || d.state === UPowerDeviceState.PendingCharge
            || d.state === UPowerDeviceState.FullyCharged;
    }

    /** ---- kind ---- */

    /**
     * The device class, as a token the glyph table below and the rows use.
     *
     * BlueZ's icon class is read first for a Bluetooth row because it is the
     * most specific thing anyone publishes about the device, and because it is
     * present for a device that has never been connected to anything (a Joy-Con
     * is `input-gaming` while merely paired). UPower's icon name is the same
     * vocabulary for the devices BlueZ does not describe — a HID dongle — and
     * its type is the fallback when even that is empty.
     */
    function kindOf(bt, up) {
        var k = kindFromIcon(bt ? bt.icon : "");
        if (k.length)
            return k;
        k = kindFromIcon(up ? up.iconName : "");
        if (k.length)
            return k;
        k = kindFromType(up ? up.type : -1);
        if (k.length)
            return k;
        return kindFromName(bt ? (bt.deviceName || bt.name) : (up ? up.model : ""));
    }

    /** Freedesktop icon classes, shared by BlueZ's icon and UPower's icon name. */
    function kindFromIcon(icon) {
        var i = String(icon || "").toLowerCase().replace(/-symbolic$/, "");
        if (!i.length)
            return "";
        if (i.indexOf("input-mouse") === 0 || i.indexOf("input-touchpad") === 0
            || i.indexOf("input-tablet") === 0 || i.indexOf("input-pen") === 0)
            return "mouse";
        if (i.indexOf("input-keyboard") === 0)
            return "keyboard";
        if (i.indexOf("input-gaming") === 0 || i.indexOf("input-joystick") === 0
            || i.indexOf("input-wheel") === 0)
            return "gamepad";
        if (i.indexOf("audio-") === 0)
            return "speaker";
        if (i.indexOf("multimedia-player") === 0)
            return "music";
        if (i.indexOf("video-display") === 0 || i.indexOf("computer") === 0)
            return "monitor";
        if (i.indexOf("camera") === 0 || i.indexOf("video") === 0)
            return "camera";
        if (i.indexOf("phone") === 0 || i.indexOf("smartphone") === 0)
            return "smartphone";
        return "";
    }

    /** UPower's own types, for the peripherals BlueZ does not describe. */
    function kindFromType(t) {
        switch (t) {
        case UPowerDeviceType.Mouse: case UPowerDeviceType.Touchpad:
        case UPowerDeviceType.Tablet: case UPowerDeviceType.Pen: return "mouse";
        case UPowerDeviceType.Keyboard: return "keyboard";
        case UPowerDeviceType.GamingInput: case UPowerDeviceType.RemoteControl: return "gamepad";
        case UPowerDeviceType.Headset: case UPowerDeviceType.Headphones:
        case UPowerDeviceType.Speakers: case UPowerDeviceType.OtherAudio: return "speaker";
        case UPowerDeviceType.MediaPlayer: return "music";
        case UPowerDeviceType.Monitor: case UPowerDeviceType.Computer: return "monitor";
        case UPowerDeviceType.Phone: case UPowerDeviceType.Modem: return "smartphone";
        case UPowerDeviceType.Camera: return "camera";
        }
        return "";
    }

    /**
     * Last resort: the device's own name. Some HID dongles publish a model
     * ("MX Master 3") and nothing else about what they are, and a wrong-but-
     * useful glyph beats the generic Bluetooth mark they would otherwise get.
     * Deliberately narrow — only words that name a class outright.
     */
    function kindFromName(n) {
        var s = String(n || "").toLowerCase();
        if (!s.length)
            return "";
        if (/head(set|phone)|earbud|earphone|airpod|buds|speaker/.test(s)) return "speaker";
        if (/joy-?con|gamepad|controller|xbox|dualshock|dualsense/.test(s)) return "gamepad";
        if (/mouse|trackball/.test(s)) return "mouse";
        if (/keyboard|keypad/.test(s)) return "keyboard";
        return "";
    }

    /** Kind token to a glyph in components/icons/GlyphIcon.qml. */
    function glyphForKind(kind) {
        switch (kind) {
        case "mouse": case "keyboard": case "gamepad": case "speaker":
        case "music": case "monitor": case "smartphone": case "camera":
            return kind;
        }
        return "bluetooth";
    }

    /** ---- the model ---- */

    /**
     * Every peripheral, one row each: the Bluetooth devices BlueZ knows (in its
     * own order, which the drill-in re-sorts for display), then the UPower
     * peripherals no Bluetooth device claimed — a dongle, or a Bluetooth
     * device's supply whose path did not yield an address.
     *
     * The dedupe is the whole point of the key: whichever source a row started
     * from, a MAC already in `seen` cannot become a second row.
     */
    readonly property var rows: buildRows(btDevices, upPeripherals)

    /**
     * Both lists in, one row per device out. Takes its sources as arguments
     * rather than reading the properties so a row can be built and checked
     * against a described device — the dedupe below is the part worth being able
     * to see rather than infer.
     */
    function buildRows(btList, upList) {
        void revision;
        var out = [];
        var seen = {};
        var byMac = {};
        var i;

        for (i = 0; i < upList.length; i++) {
            var mac = macOf(upList[i]);
            if (mac.length)
                byMac[mac] = upList[i];
        }

        for (i = 0; i < btList.length; i++) {
            var d = btList[i];
            if (!d)
                continue;
            var btMac = normMac(d.address);
            var key = btMac.length ? btMac : ("bt:" + String(d.dbusPath || i));
            if (seen[key])
                continue;
            seen[key] = true;
            out.push(makeRow(d, btMac.length ? (byMac[btMac] || null) : null, "bt", key));
        }

        for (i = 0; i < upList.length; i++) {
            var u = upList[i];
            var upMac = macOf(u);
            var key2 = upMac.length ? upMac : ("up:" + String(u.nativePath || i));
            if (seen[key2])
                continue;
            seen[key2] = true;
            out.push(makeRow(null, u, "usb", key2));
        }

        return out;
    }

    /**
     * One row. `source` is where the row came from — "bt" for a device BlueZ
     * knows, "usb" for a peripheral only UPower has — and it decides the tag the
     * row wears; `bt` is null on a usb row, `up` is null on a Bluetooth device
     * whose charge UPower does not publish.
     */
    function makeRow(bt, up, source, key) {
        var level = levelOf(up, bt);
        var kind = kindOf(bt, up);
        return {
            key: key,
            address: bt ? normMac(bt.address) : macOf(up),
            source: source,
            tag: source === "usb" ? "USB" : "",
            bt: bt,
            up: up,
            name: bt ? (bt.deviceName || bt.name || "Unknown")
                : ((up && up.model && up.model.length) ? up.model : "Unknown"),
            kind: kind,
            glyph: glyphForKind(kind),
            connected: bt ? bt.connected === true : (source === "usb"),
            paired: bt ? bt.paired === true : false,
            state: bt ? bt.state : -1,
            stateLabel: stateLabelOf(bt, source),
            level: level,
            /** Which source the percentage came from; "" for no reading. */
            reading: level < 0 ? "" : ((up && pct(up) >= 0) ? "upower" : "bluez"),
            charging: up ? up.state === UPowerDeviceState.Charging : false,
            pending: up ? up.state === UPowerDeviceState.PendingCharge : false,
            full: up ? up.state === UPowerDeviceState.FullyCharged : false,
            onPower: onPowerOf(up),
            low: level >= 0 && !onPowerOf(up) && level <= lowAt
        };
    }

    /**
     * The one phrase a row uses for what the device is doing, so the connected
     * block, the nearby list and the link row cannot word the same state three
     * ways. Empty is a real answer: an unpaired device has nothing to say about
     * itself that its own Pair control does not already say.
     */
    function stateLabelOf(bt, source) {
        if (!bt)
            return source === "usb" ? "Attached" : "";
        if (typeof BluetoothDeviceState !== "undefined") {
            if (bt.state === BluetoothDeviceState.Connecting) return "Connecting…";
            if (bt.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        }
        if (bt.connected === true)
            return "Connected";
        if (bt.paired === true)
            return "Paired";
        return "";
    }

    /** Rows for the drill-in's CONNECTED block: Bluetooth-connected, plus dongles. */
    readonly property var connected: rows.filter(function(r) { return r && r.connected; })

    /** Rows for the NEARBY list: a device BlueZ knows that is not connected. */
    readonly property var nearby: rows.filter(function(r) { return r && r.source === "bt" && !r.connected; })

    /** The model's row for a MAC, or null. */
    function forAddress(mac) {
        var k = normMac(mac);
        if (!k.length)
            return null;
        for (var i = 0; i < rows.length; i++)
            if (rows[i].key === k)
                return rows[i];
        return null;
    }

    /**
     * Connected Bluetooth devices, the count the link row quotes. Counted off
     * the model rows rather than the raw device list, so a device BlueZ happens
     * to expose twice is still one — the link row's "+1" has to agree with the
     * rows in the drill-in it points at.
     */
    readonly property int connectedCount: rows.filter(function(r) {
        return r && r.connected && r.source === "bt";
    }).length

    /**
     * The lowest charge among peripherals that are actually in use and not on
     * power: the link row's warning badge. A peripheral sitting on a dock at 20%
     * is not a problem, and one that is merely paired and put away is not either.
     */
    readonly property int lowestPct: {
        void revision;
        var low = -1;
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            if (!r || !r.connected || r.onPower || r.level < 0)
                continue;
            if (low < 0 || r.level < low)
                low = r.level;
        }
        return low;
    }

    /** ---- low-charge notifications ---- */

    property var notified: ({})

    function refresh() {
        var seen = {};
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            if (!r || r.level < 0)
                continue;
            seen[r.key] = true;
            if (r.connected && !r.onPower && r.level <= lowAt) {
                if (Flags.periphLowNotify && !notified[r.key]) {
                    notified[r.key] = true;
                    notifyProc.command = ["notify-send", "-a", "SilhouetteShell", "-i", "battery-caution",
                        r.name + " at " + r.level + "%", "Charge it soon"];
                    notifyProc.running = true;
                }
            } else {
                delete notified[r.key];
            }
        }
        for (var k in notified)
            if (!seen[k])
                delete notified[k];
    }

    onRevisionChanged: refresh()

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: notifyProc
    }

    /**
     * The two devices, watched one at a time. BlueZ and UPower both publish
     * per-device properties that no list binding would notice changing, so every
     * device in both models holds a Connections and bumps the model when one of
     * the properties a row is built from moves.
     */
    Instantiator {
        model: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.devices : null
        onObjectAdded: root.bump()
        onObjectRemoved: root.bump()
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() { root.bump() }
            function onPairedChanged() { root.bump() }
            function onStateChanged() { root.bump() }
            function onBatteryChanged() { root.bump() }
            function onBatteryAvailableChanged() { root.bump() }
            function onNameChanged() { root.bump() }
            function onDeviceNameChanged() { root.bump() }
            function onIconChanged() { root.bump() }
        }
    }

    Instantiator {
        model: (typeof UPower !== "undefined" && UPower) ? UPower.devices : null
        onObjectAdded: root.bump()
        onObjectRemoved: root.bump()
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPercentageChanged() { root.bump() }
            function onStateChanged() { root.bump() }
            function onEnergyChanged() { root.bump() }
            function onEnergyCapacityChanged() { root.bump() }
            function onReadyChanged() { root.bump() }
            function onIsPresentChanged() { root.bump() }
            function onModelChanged() { root.bump() }
            function onIconNameChanged() { root.bump() }
            function onTypeChanged() { root.bump() }
            function onNativePathChanged() { root.bump() }
        }
    }
}
