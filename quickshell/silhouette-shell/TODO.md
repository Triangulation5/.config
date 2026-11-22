# Project TODO

## Rewrite High-Impact Shell Backends in Rust (`silhouette-tools`)

Gate all new Rust subcommands behind `Flags.useRustTools` and keep the existing
shell/Python scripts as fallbacks.

1. ~~**PipeWire Privacy Monitor (`services/Privacy.qml`)**~~ *(Done — `silhouette-tools privacy-watch` with `wpctl status` fallback)*

2. ~~**Polkit Authentication Agent (`utils/polkit/agent.py` + `services/Polkit.qml`)**~~ *(Done — `silhouette-tools polkit-agent` with `agent.py` fallback)*

3. ~~**Shell Supervisor / Watchdog (`scripts/watchdog.sh`)**~~ *(Done — modular `silhouette-tools watchdog` with `watchdog-fallback.sh` fallback)*

4. **Bluetooth / Peripheral & Device Watcher (`services/Peripherals.qml`, `services/Devices.qml`)**
   - Replace periodic CLI polling (`bluetoothctl`, `nmcli`, `upower`, `pactl`)
     with a single event-driven `zbus` watcher subscribed to BlueZ,
     NetworkManager, and UPower D-Bus signals.

5. **Launcher Fuzzy Matcher (`utils/launcher/fuzzy.js`, `utils/launcher/emojis.js`)**
   - Optional speed boost for large app/emoji/file lists: a persistent
     stdin/stdout `silhouette-tools` matcher using `nucleo-matcher` for
     sub-millisecond keystroke scoring.
