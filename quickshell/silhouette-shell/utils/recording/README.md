# Recording helpers

- portal_capture.py: portal handshake (D-Bus), gst + ffmpeg orchestration.
- framepump.rs: native frame-rate probe, frame alignment and ffmpeg finalisation (std-only Rust). Build with ./build.sh; binary lands in bin/framepump-<arch>.

portal_capture.py uses the binary when present and otherwise runs the equivalent pure-Python loop. Set SILHOUETTE_NO_NATIVE=1 to force the fallback.
