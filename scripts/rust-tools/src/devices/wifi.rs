use serde::Serialize;
use std::collections::HashMap;
use zbus::{
    blocking::Connection,
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

const NM_DEST: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const NM_IFACE: &str = "org.freedesktop.NetworkManager";
const NM_DEV_IFACE: &str = "org.freedesktop.NetworkManager.Device";
const NM_WIFI_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const NM_AP_IFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
const NM_SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const NM_SETTINGS_IFACE: &str = "org.freedesktop.NetworkManager.Settings";
const NM_CONN_IFACE: &str = "org.freedesktop.NetworkManager.Settings.Connection";
const DBUS_PROPS_IFACE: &str = "org.freedesktop.DBus.Properties";

/// NM_DEVICE_TYPE_WIFI = 2
const NM_DEVICE_TYPE_WIFI: u32 = 2;

#[derive(Serialize)]
pub(crate) struct WifiState {
    #[serde(rename = "securityMap")]
    pub(crate) security_map: HashMap<String, String>,
    #[serde(rename = "knownProfiles")]
    pub(crate) known_profiles: HashMap<String, bool>,
}

fn get_prop(
    conn: &Connection,
    path: &str,
    iface: &str,
    prop: &str,
) -> Option<OwnedValue> {
    let reply = conn
        .call_method(
            Some(NM_DEST),
            path,
            Some(DBUS_PROPS_IFACE),
            "Get",
            &(iface, prop),
        )
        .ok()?;
    reply.body().deserialize::<OwnedValue>().ok()
}

fn wifi_device_paths(conn: &Connection) -> Vec<OwnedObjectPath> {
    let Ok(reply) = conn.call_method(
        Some(NM_DEST),
        NM_PATH,
        Some(NM_IFACE),
        "GetDevices",
        &(),
    ) else {
        return Vec::new();
    };
    let Ok(devices) = reply.body().deserialize::<Vec<OwnedObjectPath>>() else {
        return Vec::new();
    };
    devices
        .into_iter()
        .filter(|dev| {
            get_prop(conn, dev.as_str(), NM_DEV_IFACE, "DeviceType")
                .and_then(|v| u32::try_from(&v).ok())
                == Some(NM_DEVICE_TYPE_WIFI)
        })
        .collect()
}

fn format_security(flags: u32, wpa_flags: u32, rsn_flags: u32) -> String {
    let mut parts = Vec::new();
    if (flags & 0x1) != 0 && wpa_flags == 0 && rsn_flags == 0 {
        parts.push("WEP");
    }
    if wpa_flags != 0 {
        parts.push("WPA1");
    }
    if rsn_flags != 0 {
        if (rsn_flags & 0x400) != 0 {
            parts.push("WPA3");
        } else {
            parts.push("WPA2");
        }
    }
    parts.join(" ")
}

/// Query NetworkManager directly over D-Bus for AP security strings and known
/// 802-11-wireless connection profile names in a single process invocation.
pub(crate) fn query_state() -> Result<WifiState, String> {
    let conn = Connection::system().map_err(|e| format!("system bus: {e}"))?;
    let mut security_map: HashMap<String, String> = HashMap::new();
    let mut known_profiles: HashMap<String, bool> = HashMap::new();

    for dev in wifi_device_paths(&conn) {
        let Ok(reply) = conn.call_method(
            Some(NM_DEST),
            dev.as_str(),
            Some(NM_WIFI_IFACE),
            "GetAllAccessPoints",
            &(),
        ) else {
            continue;
        };
        let Ok(aps) = reply.body().deserialize::<Vec<OwnedObjectPath>>() else {
            continue;
        };
        for ap in aps {
            let Some(ssid_val) = get_prop(&conn, ap.as_str(), NM_AP_IFACE, "Ssid") else {
                continue;
            };
            let Ok(bytes) = Vec::<u8>::try_from(ssid_val) else {
                continue;
            };
            let ssid = String::from_utf8_lossy(&bytes).into_owned();
            if ssid.is_empty() {
                continue;
            }
            let flags = get_prop(&conn, ap.as_str(), NM_AP_IFACE, "Flags")
                .and_then(|v| u32::try_from(&v).ok())
                .unwrap_or(0);
            let wpa = get_prop(&conn, ap.as_str(), NM_AP_IFACE, "WpaFlags")
                .and_then(|v| u32::try_from(&v).ok())
                .unwrap_or(0);
            let rsn = get_prop(&conn, ap.as_str(), NM_AP_IFACE, "RsnFlags")
                .and_then(|v| u32::try_from(&v).ok())
                .unwrap_or(0);
            let sec = format_security(flags, wpa, rsn);
            let entry = security_map.entry(ssid).or_default();
            if entry.is_empty() || sec.len() > entry.len() {
                *entry = sec;
            }
        }
    }

    if let Ok(reply) = conn.call_method(
        Some(NM_DEST),
        NM_SETTINGS_PATH,
        Some(NM_SETTINGS_IFACE),
        "ListConnections",
        &(),
    ) {
        if let Ok(conns) = reply.body().deserialize::<Vec<OwnedObjectPath>>() {
            for cpath in conns {
                let Ok(sreply) = conn.call_method(
                    Some(NM_DEST),
                    cpath.as_str(),
                    Some(NM_CONN_IFACE),
                    "GetSettings",
                    &(),
                ) else {
                    continue;
                };
                let Ok(settings) = sreply
                    .body()
                    .deserialize::<HashMap<String, HashMap<String, OwnedValue>>>()
                else {
                    continue;
                };
                let Some(conn_sec) = settings.get("connection") else {
                    continue;
                };
                let conn_type = conn_sec
                    .get("type")
                    .and_then(|v| String::try_from(v.clone()).ok())
                    .unwrap_or_default();
                if conn_type != "802-11-wireless" {
                    continue;
                }
                if let Some(id) = conn_sec
                    .get("id")
                    .and_then(|v| String::try_from(v.clone()).ok())
                {
                    if !id.is_empty() {
                        known_profiles.insert(id, true);
                    }
                }
            }
        }
    }

    Ok(WifiState {
        security_map,
        known_profiles,
    })
}

/// Request a Wi-Fi scan on all wireless devices directly via NetworkManager D-Bus.
pub(crate) fn request_rescan() -> Result<(), String> {
    let conn = Connection::system().map_err(|e| format!("system bus: {e}"))?;
    let opts: HashMap<&str, Value<'_>> = HashMap::new();
    for dev in wifi_device_paths(&conn) {
        let _ = conn.call_method(
            Some(NM_DEST),
            dev.as_str(),
            Some(NM_WIFI_IFACE),
            "RequestScan",
            &(opts.clone(),),
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_ap_security_flags() {
        assert_eq!(format_security(0, 0, 0), "");
        assert_eq!(format_security(0x1, 0, 0), "WEP");
        assert_eq!(format_security(0x1, 0, 0x100), "WPA2");
        assert_eq!(format_security(0x1, 0, 0x400), "WPA3");
        assert_eq!(format_security(0x1, 0x100, 0x100), "WPA1 WPA2");
    }
}
