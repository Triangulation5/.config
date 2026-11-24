//! framepump: the raw-video half of portal_capture.py, in Rust (std only).
//!
//! Reads raw I420 from stdin (gst's fdsink), watches the head of the stream to
//! measure the real frame rate, starts ffmpeg with that rate, replays the
//! probed frames, then re-aligns every chunk to whole frames so ffmpeg never
//! sees a short packet. On EOF it closes ffmpeg's stdin and asks it to finish
//! with SIGINT so the mp4 trailer gets written.
//!
//! Usage:
//!   framepump --frame-bytes N --fps N --stderr-file PATH
//!             [--probe-seconds S] [--max-probe-bytes N] [--placeholder STR]
//!             -- ffmpeg ARGS...      (STR in ARGS is replaced by the rate)
//!
//! stdout: one line `rate <float>` once ffmpeg is running.
//! Exit:   0 = clean finish, 1 = no frames / bad args / ffmpeg crashed.

mod portal;
mod portal_dbus;
mod portal_session;

use std::fmt::Write as FmtWrite;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::os::raw::{c_int, c_short, c_ulong};
use std::os::unix::io::FromRawFd;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: c_short,
    revents: c_short,
}

extern "C" {
    fn poll(fds: *mut PollFd, n: c_ulong, timeout: c_int) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn signal(sig: c_int, handler: usize) -> usize;
}

pub(crate) const SIGINT: c_int = 2;
pub(crate) const SIGTERM: c_int = 15;
pub(crate) const SIG_DFL: usize = 0;
const SIG_IGN: usize = 1;
const POLLIN: c_short = 1;
pub(crate) const CHUNK: usize = 1 << 18;
pub(crate) const NO_FRAME_LIMIT: Duration = Duration::from_secs(30);

/// Reusable single-fd poller that avoids recreating `PollFd` on every iteration.
pub(crate) struct FdPoller {
    pfd: PollFd,
}

impl FdPoller {
    pub(crate) fn new(fd: c_int) -> Self {
        Self {
            pfd: PollFd {
                fd,
                events: POLLIN,
                revents: 0,
            },
        }
    }

    pub(crate) fn wait_readable(&mut self, ms: i32) -> bool {
        self.pfd.revents = 0;
        // POLLHUP/POLLERR also return > 0, and the following read reports EOF.
        unsafe { poll(&mut self.pfd, 1, ms) > 0 }
    }
}

/// Read-indexed frame queue that avoids `Vec::drain` memmoves on every write
/// while keeping memory bounded via amortized compaction.
pub(crate) struct FrameQueue {
    buf: Vec<u8>,
    offset: usize,
}

impl FrameQueue {
    pub(crate) fn from_vec(buf: Vec<u8>) -> Self {
        Self { buf, offset: 0 }
    }

    pub(crate) fn extend_from_slice(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(data);
    }

    /// Writes all currently buffered whole frames to `writer`.
    /// Returns `false` if writing failed.
    pub(crate) fn write_whole_frames<W: Write>(
        &mut self,
        frame_bytes: usize,
        writer: &mut W,
    ) -> bool {
        let avail = self.buf.len() - self.offset;
        let whole = avail - (avail % frame_bytes);
        if whole == 0 {
            return true;
        }
        if writer
            .write_all(&self.buf[self.offset..self.offset + whole])
            .is_err()
        {
            return false;
        }
        self.offset += whole;
        if self.offset == self.buf.len() {
            self.buf.clear();
            self.offset = 0;
        } else if self.offset >= CHUNK {
            let rem = self.buf.len() - self.offset;
            self.buf.copy_within(self.offset.., 0);
            self.buf.truncate(rem);
            self.offset = 0;
        }
        true
    }
}

/// Formats a frame rate with up to 3 decimal places using a pre-allocated buffer.
pub(crate) fn format_rate(rate: f64) -> String {
    let mut s = String::with_capacity(16);
    let _ = write!(s, "{:.3}", rate);
    while s.ends_with('0') {
        s.pop();
    }
    if s.ends_with('.') {
        s.pop();
    }
    s
}

fn fail(msg: &str) -> ! {
    eprintln!("{}", msg);
    std::process::exit(1);
}

struct Opts {
    frame_bytes: usize,
    fps: f64,
    stderr_file: String,
    probe_secs: f64,
    max_probe: usize,
    placeholder: String,
    cmd: Vec<String>,
}

fn parse() -> Opts {
    let mut o = Opts {
        frame_bytes: 0,
        fps: 30.0,
        stderr_file: String::new(),
        probe_secs: 2.0,
        max_probe: 64 << 20,
        placeholder: "--rate-placeholder--".into(),
        cmd: vec![],
    };
    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        if a == "--" {
            o.cmd = it.collect();
            break;
        }
        let v = it.next().unwrap_or_else(|| fail(&format!("missing value for {}", a)));
        match a.as_str() {
            "--frame-bytes" => o.frame_bytes = v.parse().unwrap_or(0),
            "--fps" => o.fps = v.parse().unwrap_or(30.0),
            "--stderr-file" => o.stderr_file = v,
            "--probe-seconds" => o.probe_secs = v.parse().unwrap_or(2.0),
            "--max-probe-bytes" => o.max_probe = v.parse().unwrap_or(64 << 20),
            "--placeholder" => o.placeholder = v,
            _ => fail(&format!("unknown option {}", a)),
        }
    }
    if o.frame_bytes == 0 || o.cmd.is_empty() {
        fail("framepump: --frame-bytes and an ffmpeg command are required");
    }
    o
}

fn wait_child(child: &mut Child, limit: Duration) {
    let t0 = Instant::now();
    while t0.elapsed() < limit {
        if let Ok(Some(_)) = child.try_wait() {
            return;
        }
        sleep(Duration::from_millis(50));
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn main() {
    let raw_args: Vec<String> = std::env::args().skip(1).collect();
    if raw_args.first().map(|s| s.as_str()) == Some("--portal") {
        portal::run_portal(&raw_args[1..]);
    }
    let o = parse();

    unsafe {
        signal(SIGINT, SIG_IGN);
        signal(SIGTERM, SIG_IGN);
    }

    let mut input = unsafe { File::from_raw_fd(0) };
    let mut poller = FdPoller::new(0);
    let mut buf = vec![0u8; CHUNK];
    let mut head: Vec<u8> = Vec::new();

    // Probe the head of the stream.
    let t0 = Instant::now();
    loop {
        let el = t0.elapsed();
        let have_frame = head.len() >= o.frame_bytes;
        if have_frame && el.as_secs_f64() >= o.probe_secs {
            break;
        }
        if !have_frame && el >= NO_FRAME_LIMIT {
            break;
        }
        if !poller.wait_readable(200) {
            continue;
        }
        match input.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => head.extend_from_slice(&buf[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
        if head.len() >= o.max_probe {
            break;
        }
    }
    let elapsed = t0.elapsed().as_secs_f64().max(0.001);
    if head.len() < o.frame_bytes {
        fail(&format!("Screen share produced no frames in {:.1}s", elapsed));
    }
    let rate = (head.len() as f64 / o.frame_bytes as f64 / elapsed).clamp(0.5, 240.0);
    let rate_str = format_rate(rate);

    let mut args: Vec<String> = o
        .cmd
        .iter()
        .map(|a| if *a == o.placeholder { rate_str.clone() } else { a.clone() })
        .collect();
    if rate > o.fps * 1.1 && args.len() >= 2 {
        // Drop surplus frames: insert before the output path.
        let at = args.len() - 1;
        args.splice(at..at, ["-vf".to_string(), format!("fps={}", o.fps as i64)]);
    }

    let err_out = if o.stderr_file.is_empty() {
        Stdio::null()
    } else {
        match File::create(&o.stderr_file) {
            Ok(f) => Stdio::from(f),
            Err(_) => Stdio::null(),
        }
    };
    let mut cmd = Command::new(&args[0]);
    cmd.args(&args[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(err_out);
    unsafe {
        cmd.pre_exec(|| {
            signal(SIGINT, SIG_DFL);
            signal(SIGTERM, SIG_DFL);
            Ok(())
        });
    }
    let mut ff = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => fail(&format!("Could not start ffmpeg: {}", e)),
    };
    let mut ff_in = ff.stdin.take();

    println!("rate {}", rate);
    let _ = std::io::stdout().flush();

    // Align to whole frames and feed ffmpeg using a read-indexed queue.
    let mut queue = FrameQueue::from_vec(head);
    let mut ff_died = false;

    loop {
        let ok = ff_in
            .as_mut()
            .is_some_and(|w| queue.write_whole_frames(o.frame_bytes, w));
        if !ok {
            ff_died = true;
            break;
        }

        if let Ok(Some(_)) = ff.try_wait() {
            ff_died = true;
            break;
        }

        if !poller.wait_readable(200) {
            continue;
        }

        match input.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => queue.extend_from_slice(&buf[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }

    // Wrap ffmpeg up. The pulse inputs are live devices that never hit EOF, so
    // closing the pipe is not enough: SIGINT makes it write the mp4 trailer.
    drop(ff_in.take());
    let status = ff.try_wait().ok().flatten();
    if status.is_none() {
        unsafe { kill(ff.id() as c_int, SIGINT) };
    }
    wait_child(&mut ff, Duration::from_secs(20));

    let mut code = 0;
    let crashed = ff_died && ff.try_wait().ok().flatten().map_or(false, |s| !s.success());
    if crashed {
        code = 1;
        let err = fs::read_to_string(&o.stderr_file).unwrap_or_default();
        let err = err.trim();
        if err.is_empty() {
            eprintln!("ffmpeg failed early");
        } else {
            eprintln!("ffmpeg failed: {}", err.chars().take(500).collect::<String>());
        }
    }
    if !o.stderr_file.is_empty() {
        let _ = fs::remove_file(&o.stderr_file);
    }
    std::process::exit(code);
}