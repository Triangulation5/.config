# Recording helpers

- `run.sh`: launcher used by `services/ScreenRec.qml`. Runs the native Rust `framepump --portal` binary when available and `useRustTools` is enabled, otherwise falls back to `portal_capture.py`. Set `SILHOUETTE_NO_NATIVE=1` to force the Python fallback.
- `framepump.rs` + `portal.rs`: std-only Rust screen-capture pipeline (native `libdbus-1.so.3` `org.freedesktop.portal.ScreenCast` handshake, `gst-launch-1.0` PipeWire capture, frame-rate probe, frame alignment, and `ffmpeg` finalization). Build with `./build.sh`; binary lands in `bin/framepump-<arch>`.
- `portal_capture.py`: Python fallback implementing the same portal handshake + capture loop.
