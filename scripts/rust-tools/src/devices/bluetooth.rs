use std::collections::HashMap;
use zbus::{
    blocking::Connection,
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

const BLUEZ_DEST: &str = "org.bluez";
const BLUEZ_DEVICE_IFACE: &str = "org.bluez.Device1";
const DBUS_OM_IFACE: &str = "org.freedesktop.DBus.ObjectManager";
const DBUS_PROPS_IFACE: &str = "org.freedesktop.DBus.Properties";

fn normalize_mac(mac: &str) -> String {
    mac.chars()
        .filter(|c| c.is_ascii_hexdigit())
        .map(|c| c.to_ascii_uppercase())
        .collect()
}

fn find_device_path(conn: &Connection, target_mac: &str) -> Result<OwnedObjectPath, String> {
    let reply = conn
        .call_method(
            Some(BLUEZ_DEST),
            "/",
            Some(DBUS_OM_IFACE),
            "GetManagedObjects",
            &(),
        )
        .map_err(|e| format!("bluez GetManagedObjects: {e}"))?;

    let objects: HashMap<OwnedObjectPath, HashMap<String, HashMap<String, OwnedValue>>> = reply
        .body()
        .deserialize()
        .map_err(|e| format!("bluez parse objects: {e}"))?;

    let wanted = normalize_mac(target_mac);
    for (path, ifaces) in objects {
        let Some(dev) = ifaces.get(BLUEZ_DEVICE_IFACE) else {
            continue;
        };
        if let Some(addr_val) = dev.get("Address") {
            if let Ok(addr) = String::try_from(addr_val.clone()) {
                if normalize_mac(&addr) == wanted {
                    return Ok(path);
                }
            }
        }
    }

    Err(format!("bluez device {target_mac} not found"))
}

/// Pair, trust, and connect a Bluetooth device directly via BlueZ D-Bus,
/// replacing the chained `bluetoothctl` shell command.
pub(crate) fn pair_trust_connect(mac: &str) -> Result<(), String> {
    let conn = Connection::system().map_err(|e| format!("system bus: {e}"))?;
    let path = find_device_path(&conn, mac)?;

    if let Err(err) = conn.call_method(
        Some(BLUEZ_DEST),
        path.as_str(),
        Some(BLUEZ_DEVICE_IFACE),
        "Pair",
        &(),
    ) {
        let msg = err.to_string();
        if !msg.contains("AlreadyExists") {
            return Err(format!("bluez Pair failed: {msg}"));
        }
    }

    conn.call_method(
        Some(BLUEZ_DEST),
        path.as_str(),
        Some(DBUS_PROPS_IFACE),
        "Set",
        &(BLUEZ_DEVICE_IFACE, "Trusted", Value::from(true)),
    )
    .map_err(|e| format!("bluez Set Trusted failed: {e}"))?;

    conn.call_method(
        Some(BLUEZ_DEST),
        path.as_str(),
        Some(BLUEZ_DEVICE_IFACE),
        "Connect",
        &(),
    )
    .map_err(|e| format!("bluez Connect failed: {e}"))?;

    Ok(())
}
