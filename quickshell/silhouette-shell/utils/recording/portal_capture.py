#!/usr/bin/env python3
"""
Wayland screen capture through the ScreenCast portal, encoded by ffmpeg.

Opens an org.freedesktop.portal.ScreenCast session (the compositor's
screen-share portal — on Hyprland this shows its picker once and, with
persist_mode, remembers the choice for later recordings), receives the
PipeWire connection fd, pipes the raw video through gst
(pipewiresrc -> videoconvert -> videorate -> raw I420) into ffmpeg, which
does the libx264 encode and optional pulse audio. No root needed.

The raw video pipe carries no timestamps and the screencast node is produced
on damage, so the frame rate is measured off the head of the stream and handed
to ffmpeg (which then trims down to the requested fps when the source is
faster). The frames read during that measurement are replayed into ffmpeg, so
nothing recorded while probing is lost. gst hands out arbitrary chunks and
ffmpeg aborts the whole file on a packet that is not exactly one frame, so
chunks are re-aligned to whole frames and a trailing partial frame is dropped.

Stopping closes the video pipe and asks ffmpeg to wrap up with SIGINT, which is
what writes the mp4 trailer — the pulse inputs are live devices that never
reach EOF on their own, and killing ffmpeg would leave an unplayable file.

The shell watches stdout: `capture-started` is printed once gst and ffmpeg are
actually running, so the shell only shows a live recording from that point (a
run is idle while the share picker is still up). Everything that goes wrong is
written to stderr, which the shell surfaces as the failure notification.

Usage:
  portal_capture.py --output FILE [--fps N] [--crf N] [--cursor yes|no]
                    [--sink NAME] [--mic NAME]

Exit codes: 0 = recording finished and the output file is valid,
            1 = cancelled / failed / empty output.
"""

import argparse
import os
import select
import signal
import subprocess
import sys
import time

import dbus
import dbus.mainloop.glib
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

PORTAL_NAME = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST_IFACE = "org.freedesktop.portal.ScreenCast"
PIPEWIRE_IFACE = "org.freedesktop.portal.PipeWire"
REQUEST_IFACE = "org.freedesktop.portal.Request"

# ScreenCast source types / cursor modes / persist modes (portal spec).
SOURCE_MONITOR = 1
CURSOR_EMBEDDED = 1
CURSOR_METADATA = 2
PERSIST_PERMANENT = 2  # xdg-desktop-portal-hyprland accepts 1 and 2 only

PICKER_TIMEOUT = 180  # seconds to wait for the user to pick a source
# dbus-python defaults to a 25s reply timeout, which kills the call with NoReply
# while the user is still looking at the picker. The blocking call waits longer
# than the picker does, so the PICKER_TIMEOUT above is what actually ends it.
DBUS_TIMEOUT = (PICKER_TIMEOUT + 30) * 1000  # milliseconds

# How long the head of the raw stream is watched to work out the frame rate the
# compositor is really producing, and how much of it may be held back to be
# replayed into ffmpeg once that number is known (64 MiB is about 1.4s at
# 1080p60, which is enough for a decent estimate without eating the machine).
RATE_PROBE_SECONDS = 2.0
MAX_PROBE_BYTES = 64 * 1024 * 1024
RATE_PLACEHOLDER = "--rate-placeholder--"


def write_all(stream, data):
    """Write every byte of `data`, coping with short writes."""
    view = memoryview(data)
    while view:
        view = view[stream.write(view):]


def restore_token_path():
    """Where the portal-issued restore token is cached between recordings."""
    cache = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    return os.path.join(cache, "silhouette", "rec-restore-token")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--crf", type=int, default=18)
    parser.add_argument("--cursor", choices=["yes", "no"], default="yes")
    parser.add_argument("--sink", default="")
    parser.add_argument("--mic", default="")
    parser.add_argument("--persist", type=int, default=PERSIST_PERMANENT,
                        help="portal persist_mode (0 none, 1 session, 2 permanent, 3 both)")
    return parser.parse_args()


def main():
    args = parse_args()

    # A sentinel left behind by a crashed run would make the shell report a
    # recording that is not happening.
    try:
        os.unlink(args.output + ".capturing")
    except OSError:
        pass

    # Registered before the handshake so a stop signal is honoured even while
    # the picker is still up; the handshake heartbeat polls this flag.
    stopping = [False]

    def stop_handler(signum, frame):
        stopping[0] = True

    signal.signal(signal.SIGINT, stop_handler)
    signal.signal(signal.SIGTERM, stop_handler)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    portal = bus.get_object(PORTAL_NAME, PORTAL_PATH)
    screencast = dbus.Interface(portal, SCREENCAST_IFACE)
    pipewire = dbus.Interface(portal, PIPEWIRE_IFACE)

    token_n = [0]

    def token():
        token_n[0] += 1
        return "quickshell_%d_%d" % (os.getpid(), token_n[0])

    def wait_response(method, *args, **kwargs):
        """Call a portal method returning a Request path and block until its
        Response signal arrives. Returns (response_code, results_dict)."""
        loop = GLib.MainLoop()
        out = {}

        def respond(code, results):
            out["code"] = int(code)
            out["results"] = results
            loop.quit()

        def beat():
            # Heartbeat: keeps Python signal handlers (SIGINT/SIGTERM)
            # responsive while the loop waits on the picker, and aborts the
            # wait when a stop signal arrived.
            if stopping[0]:
                loop.quit()
                return False
            return True

        request_path = method(*args, timeout=DBUS_TIMEOUT, **kwargs)
        req = bus.get_object(PORTAL_NAME, request_path)
        req_iface = dbus.Interface(req, REQUEST_IFACE)
        req_iface.connect_to_signal("Response", respond)
        GLib.timeout_add(200, beat)
        GLib.timeout_add_seconds(PICKER_TIMEOUT, loop.quit)
        loop.run()
        if "code" not in out:
            return 2, {}
        return out["code"], out["results"]

    try:
        code, results = wait_response(
            screencast.CreateSession,
            {"handle_token": token(), "session_handle_token": token()},
        )
        if code != 0:
            print("Screen share session could not be created (portal error %d)" % code, file=sys.stderr)
            return 1
        session = str(results["session_handle"])

        cursor_mode = CURSOR_EMBEDDED if args.cursor == "yes" else CURSOR_METADATA
        select_opts = {
            "types": dbus.UInt32(SOURCE_MONITOR),
            "multiple": dbus.Boolean(False),
            "cursor_mode": dbus.UInt32(cursor_mode),
            "persist_mode": dbus.UInt32(args.persist),
        }
        saved_token = ""
        token_path = restore_token_path()
        try:
            with open(token_path) as f:
                saved_token = f.read().strip()
        except OSError:
            pass
        if saved_token:
            select_opts["restore_token"] = saved_token

        code, results = wait_response(screencast.SelectSources, session, select_opts)
        if code != 0:
            print("Screen share selection was cancelled", file=sys.stderr)
            return 1
        # The portal issues a restore token we can replay on later runs so the
        # picker can be skipped. Cache it once a choice has been made.
        issued = results.get("restore_token", "")
        if issued and issued != saved_token:
            try:
                os.makedirs(os.path.dirname(token_path), exist_ok=True)
                with open(token_path, "w") as f:
                    f.write(str(issued))
            except OSError:
                pass

        code, results = wait_response(
            screencast.Start,
            session,
            "",
            {"handle_token": token()},
        )
        if code != 0:
            print("Screen share start was cancelled", file=sys.stderr)
            return 1

        streams = results.get("streams", [])
        if not streams:
            print("Screen share returned no streams", file=sys.stderr)
            return 1
        props = streams[0][1]
        size = props.get("size", (0, 0))
        width, height = int(size[0]), int(size[1])
        if width <= 0 or height <= 0:
            print("Screen share stream has no usable size", file=sys.stderr)
            return 1

        conn_fd = None
        try:
            conn_fd = pipewire.OpenPipeWireRemote(session, dbus.Dictionary({}, signature="sv")).take()
        except dbus.exceptions.DBusException:
            # Not every portal implements the PipeWire D-Bus interface (Hyprland
            # running the gtk backend exposes none of it). Those hand back the
            # node id only, which is still enough to read the stream.
            conn_fd = connection_fd(results)
    except dbus.exceptions.DBusException as exc:
        print("Screen share portal error: %s" % exc, file=sys.stderr)
        return 1

    # The portal stream id pins pipewiresrc to the screen share node instead
    # of letting autoconnect grab the first video source it finds (which on a
    # laptop is often a camera).
    stream_id = int(streams[0][0])
    if conn_fd is not None:
        # Normal route: the portal hands over a pipewire *remote*, so gst talks
        # to that private instance over the fd it was given.
        src_args = ["fd=%d" % conn_fd, "target-object=%d" % stream_id]
        pass_fds = (conn_fd,)
    else:
        # Portals with no PipeWire D-Bus interface (Hyprland running the gtk
        # backend) hand back only the node id of a screencast node that lives in
        # the session's own pipewire, so gst connects to the local daemon and
        # picks the node out by id.
        src_args = ["target-object=%d" % stream_id]
        pass_fds = ()
    gst_cmd = [
        "gst-launch-1.0", "-q",
        "pipewiresrc",
    ] + src_args + [
        "!", "videoconvert",
        # No videorate and no framerate caps: the screencast node is only
        # produced on damage, and asking it for a fixed rate makes it reject the
        # format outright ("error set output format: -22" on Hyprland), which
        # kills the stream before a single frame lands. The real rate is
        # measured from the pipe instead and handed to ffmpeg.
        "!", "video/x-raw,format=I420",
        "!", "fdsink",
    ]

    ff_cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-probesize", "32", "-analyzeduration", "0",
        "-f", "rawvideo", "-pix_fmt", "yuv420p",
        "-s", "%dx%d" % (width, height), "-framerate", RATE_PLACEHOLDER,
        "-i", "pipe:0",
    ]

    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    server = runtime + "/pulse/native"
    inputs = []
    if args.sink:
        inputs.append(["-f", "pulse", "-server", server, "-i", args.sink + ".monitor"])
    if args.mic:
        inputs.append(["-f", "pulse", "-server", server, "-i", args.mic])
    if len(inputs) == 1:
        ff_cmd += inputs[0] + ["-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "192k"]
    elif len(inputs) == 2:
        ff_cmd += inputs[0] + inputs[1] + [
            "-filter_complex", "[1:a][2:a]amix=inputs=2:normalize=0[a]",
            "-map", "0:v", "-map", "[a]", "-c:a", "aac", "-b:a", "192k",
        ]
    else:
        ff_cmd += ["-an"]

    ff_cmd += [
        "-c:v", "libx264", "-preset", "veryfast", "-crf", str(args.crf),
        "-y", args.output,
    ]

    # A stop signal can arrive while the picker is still up, before any
    # capture process exists. Exit cleanly in that case.
    if stopping[0]:
        try:
            screencast.CloseSession(session)
        except dbus.exceptions.DBusException:
            pass
        print("Stopped before capture started", file=sys.stderr)
        return 1

    try:
        gst = subprocess.Popen(gst_cmd, stdout=subprocess.PIPE,
                               pass_fds=pass_fds)
    except OSError as exc:
        print("Could not start gst: %s" % exc, file=sys.stderr)
        return 1

    # The raw pipe carries no timestamps, so ffmpeg has to be told how fast the
    # frames arrive. The screencast node is produced on damage (a still desktop
    # trickles frames at a couple per second, a busy one at the refresh rate)
    # and refuses a fixed rate outright, so the real rate is measured off the
    # head of the stream and the frames seen there are replayed into ffmpeg, so
    # nothing recorded during the probe is lost.
    src_fd = gst.stdout.fileno()
    frame_bytes = width * height * 3 // 2
    buffered = bytearray()
    probe_start = time.time()
    while time.time() - probe_start < RATE_PROBE_SECONDS:
        chunk = os.read(src_fd, 1 << 18)
        if not chunk:
            break
        buffered += chunk
        if len(buffered) >= MAX_PROBE_BYTES:
            break
    probe_elapsed = max(0.001, time.time() - probe_start)
    if len(buffered) < frame_bytes:
        print("Screen share produced no frames in %.1fs" % probe_elapsed, file=sys.stderr)
        return 1
    src_rate = min(max(len(buffered) / frame_bytes / probe_elapsed, 0.5), 240.0)
    rate_str = ("%.3f" % src_rate).rstrip("0").rstrip(".")
    ff_cmd = [rate_str if a == RATE_PLACEHOLDER else a for a in ff_cmd]
    if src_rate > args.fps * 1.1:
        # More frames than asked for: let ffmpeg drop the surplus rather than
        # record a clip that is heavier than the requested frame rate.
        ff_cmd[-1:-1] = ["-vf", "fps=%d" % args.fps]

    # gst's errors inherit stderr so the shell's failure notification can
    # surface them; ffmpeg's go to a file read on early failure.
    ff_err_path = args.output + ".ffmpeg.err"
    ff_err = open(ff_err_path, "w")
    ffmpeg = subprocess.Popen(ff_cmd, stdin=subprocess.PIPE,
                              stdout=subprocess.DEVNULL, stderr=ff_err)

    # ffmpeg's rawvideo demuxer aborts the whole file the moment it is handed a
    # packet that is not exactly one frame ("Invalid buffer size"), and gst
    # hands out arbitrary chunks, so frames are re-aligned here and a trailing
    # partial frame is dropped instead of poisoning the output.
    pending = bytearray()

    def feed(data):
        pending.extend(data)
        whole = len(pending) - len(pending) % frame_bytes
        if whole:
            write_all(ffmpeg.stdin, pending[:whole])
            del pending[:whole]

    feed(buffered)

    # The shell watches for this sentinel: a run that is still on the share
    # picker has not produced it yet, and must not be shown as recording. It
    # cannot watch stdout for that, because StdioCollector only hands over the
    # text once the stream closes - which here is after the stop.
    marker_path = args.output + ".capturing"
    try:
        with open(marker_path, "w") as f:
            f.write("%d\n" % os.getpid())
    except OSError:
        marker_path = None

    # Frames only exist once the portal stream is live; this is the point the
    # shell can honestly call it a recording.
    print("capture-started", flush=True)
    print("source %.2f fps at %dx%d, recording at %d fps" % (src_rate, width, height, args.fps),
          file=sys.stderr)

    def finish_gst():
        if gst.poll() is None:
            gst.terminate()
        try:
            gst.wait(timeout=10)
        except subprocess.TimeoutExpired:
            gst.kill()
            gst.wait()

    def close_ff_stdin():
        """Signal EOF on the video pipe. This side belongs to us now, so
        without closing it ffmpeg would sit waiting for frames forever."""
        try:
            ffmpeg.stdin.close()
        except (OSError, ValueError):
            pass

    def drain_ffmpeg():
        """Wrap ffmpeg up and wait for the file it is writing.

        The pulse inputs are live devices that never reach EOF, so closing the
        video pipe is not enough to make ffmpeg finish: it has to be asked to.
        SIGINT is ffmpeg's own "stop and finalise" request, which is what
        writes the mp4 trailer; a kill would leave an unplayable file behind.
        """
        close_ff_stdin()
        if ffmpeg.poll() is None:
            ffmpeg.send_signal(signal.SIGINT)
        try:
            ffmpeg.wait(timeout=20)
        except subprocess.TimeoutExpired:
            ffmpeg.kill()
            ffmpeg.wait()

    try:
        while True:
            if stopping[0]:
                break
            if ffmpeg.poll() is not None:
                break
            if gst.poll() is not None:
                break
            # 0.2s timeout keeps the stop signal and the death checks above
            # responsive while the pipe is idle between frames.
            if not select.select([src_fd], [], [], 0.2)[0]:
                continue
            chunk = os.read(src_fd, 1 << 18)
            if not chunk:
                break
            feed(chunk)

        # gst is done either way, so let ffmpeg finish and write the trailer.
        finish_gst()
        crashed = not stopping[0] and ffmpeg.poll() is not None and ffmpeg.returncode != 0
        drain_ffmpeg()

        if crashed:
            err = ""
            try:
                ff_err.flush()
                with open(ff_err_path) as f:
                    err = f.read().strip()
            except OSError:
                pass
            if err:
                print("ffmpeg failed: %s" % err[:500], file=sys.stderr)
            else:
                print("ffmpeg failed early (exit %d)" % ffmpeg.returncode, file=sys.stderr)
        ff_err.close()
    finally:
        try:
            gst.stdout.close()
        except (NameError, OSError, ValueError):
            pass
        try:
            if marker_path:
                os.unlink(marker_path)
        except (OSError, NameError, TypeError):
            pass
        try:
            ff_err.close()
        except NameError:
            pass
        try:
            os.unlink(ff_err_path)
        except (OSError, NameError):
            pass
        try:
            screencast.CloseSession(session)
        except dbus.exceptions.DBusException:
            pass

    # A raw pipe delivers a partial final frame on EOF, so ffmpeg exits
    # non-zero even when every frame made it into the file. Judge success by
    # the output itself.
    if os.path.exists(args.output) and output_duration(args.output) > 0:
        return 0
    print("Recording produced no usable output", file=sys.stderr)
    return 1


def connection_fd(results):
    """Pull the pipewire remote fd out of a Start response `connections` map.

    Returns None when the portal gave no fd, so the caller can report it
    instead of failing later on an fdsink that never receives anything.
    """
    conns = results.get("connections")
    if not conns:
        return None
    entry = conns.get("pipewire")
    if entry is None:
        for value in conns.values():
            entry = value
            break
    if entry is None:
        return None
    try:
        return int(entry.take())
    except AttributeError:
        return int(entry)


def output_duration(path):
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path],
            capture_output=True, text=True, timeout=15,
        )
        return float(probe.stdout.strip())
    except (ValueError, subprocess.TimeoutExpired, OSError):
        return 0.0


if __name__ == "__main__":
    sys.exit(main())
