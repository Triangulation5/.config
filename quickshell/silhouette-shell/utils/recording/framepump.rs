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

const SIGINT: c_int = 2;
const SIGTERM: c_int = 15;
const SIG_DFL: usize = 0;
const SIG_IGN: usize = 1;
const POLLIN: c_short = 1;
const CHUNK: usize = 1 << 18;
const NO_FRAME_LIMIT: Duration = Duration::from_secs(30);

pub(crate) fn wait_readable(fd: c_int, ms: i32) -> bool {
    let mut p = PollFd { fd, events: POLLIN, revents: 0 };
    // POLLHUP/POLLERR also return > 0, and the following read reports EOF.
    unsafe { poll(&mut p, 1, ms) > 0 }
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
    // Stop is signalled by gst's EOF; a stray SIGINT/SIGTERM must not kill the
    // pump before ffmpeg is wrapped up. ffmpeg gets default handlers back.
    unsafe {
        signal(SIGINT, SIG_IGN);
        signal(SIGTERM, SIG_IGN);
    }

    let mut input = unsafe { File::from_raw_fd(0) };
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
        if !wait_readable(0, 200) {
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
    let mut rate_str = format!("{:.3}", rate);
    while rate_str.ends_with('0') {
        rate_str.pop();
    }
    if rate_str.ends_with('.') {
        rate_str.pop();
    }

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

    // Align to whole frames and feed ffmpeg.
    let mut pending: Vec<u8> = head;
    let mut ff_died = false;
    loop {
        let whole = pending.len() - pending.len() % o.frame_bytes;
        if whole > 0 {
            let ok = ff_in.as_mut().map_or(false, |w| w.write_all(&pending[..whole]).is_ok());
            if !ok {
                ff_died = true;
                break;
            }
            pending.drain(..whole);
        }
        if let Ok(Some(_)) = ff.try_wait() {
            ff_died = true;
            break;
        }
        if !wait_readable(0, 200) {
            continue;
        }
        match input.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => pending.extend_from_slice(&buf[..n]),
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
