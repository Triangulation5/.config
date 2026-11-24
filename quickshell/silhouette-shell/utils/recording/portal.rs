use crate::portal_dbus::LibDbus;
use crate::portal_session::open_screencast_session;
use crate::{format_rate, FdPoller, FrameQueue, CHUNK, NO_FRAME_LIMIT, SIGINT, SIGTERM, SIG_DFL};
use std::env;
use std::ffi::c_int;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::sleep;
use std::time::{Duration, Instant};

const RATE_PROBE_SECS: f64 = 2.0;
const MAX_PROBE_BYTES: usize = 64 << 20;

static STOPPING: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_stop(_sig: c_int) {
    STOPPING.store(true, Ordering::Relaxed);
}

extern "C" {
    fn close(fd: c_int) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn signal(sig: c_int, handler: usize) -> usize;
}

struct PortalOpts {
    output: String,
    fps: i32,
    crf: i32,
    cursor_yes: bool,
    sink: String,
    mic: String,
    persist: u32,
}

fn parse_portal_args(args: &[String]) -> PortalOpts {
    let mut o = PortalOpts {
        output: String::new(),
        fps: 30,
        crf: 18,
        cursor_yes: true,
        sink: String::new(),
        mic: String::new(),
        persist: 2,
    };
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--output" if i + 1 < args.len() => {
                o.output = args[i + 1].clone();
                i += 2;
            }
            "--fps" if i + 1 < args.len() => {
                o.fps = args[i + 1].parse().unwrap_or(30);
                i += 2;
            }
            "--crf" if i + 1 < args.len() => {
                o.crf = args[i + 1].parse().unwrap_or(18);
                i += 2;
            }
            "--cursor" if i + 1 < args.len() => {
                o.cursor_yes = args[i + 1] != "no";
                i += 2;
            }
            "--sink" if i + 1 < args.len() => {
                o.sink = args[i + 1].clone();
                i += 2;
            }
            "--mic" if i + 1 < args.len() => {
                o.mic = args[i + 1].clone();
                i += 2;
            }
            "--persist" if i + 1 < args.len() => {
                o.persist = args[i + 1].parse().unwrap_or(2);
                i += 2;
            }
            _ => i += 1,
        }
    }
    if o.output.is_empty() {
        eprintln!("framepump --portal: --output is required");
        std::process::exit(2);
    }
    o
}

fn stop_child(child: &mut Child, sig: c_int, limit: Duration) {
    if child.try_wait().ok().flatten().is_none() {
        unsafe { kill(child.id() as c_int, sig) };
    }
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

fn build_ffmpeg_args(opts: &PortalOpts, width: i32, height: i32, rate: f64) -> Vec<String> {
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let server = format!("{}/pulse/native", runtime);
    let mut ff_args: Vec<String> = vec![
        "-hide_banner".into(),
        "-loglevel".into(),
        "error".into(),
        "-probesize".into(),
        "32".into(),
        "-analyzeduration".into(),
        "0".into(),
        "-f".into(),
        "rawvideo".into(),
        "-pix_fmt".into(),
        "yuv420p".into(),
        "-s".into(),
        format!("{}x{}", width, height),
        "-framerate".into(),
        format_rate(rate),
        "-i".into(),
        "pipe:0".into(),
    ];

    let has_sink = !opts.sink.is_empty();
    let has_mic = !opts.mic.is_empty();
    if has_sink {
        ff_args.extend([
            "-f".into(),
            "pulse".into(),
            "-server".into(),
            server.clone(),
            "-i".into(),
            format!("{}.monitor", opts.sink),
        ]);
    }
    if has_mic {
        ff_args.extend([
            "-f".into(),
            "pulse".into(),
            "-server".into(),
            server,
            "-i".into(),
            opts.mic.clone(),
        ]);
    }
    match (has_sink, has_mic) {
        (true, true) => ff_args.extend([
            "-filter_complex".into(),
            "[1:a][2:a]amix=inputs=2:normalize=0[a]".into(),
            "-map".into(),
            "0:v".into(),
            "-map".into(),
            "[a]".into(),
            "-c:a".into(),
            "aac".into(),
            "-b:a".into(),
            "192k".into(),
        ]),
        (true, false) | (false, true) => ff_args.extend([
            "-map".into(),
            "0:v".into(),
            "-map".into(),
            "1:a".into(),
            "-c:a".into(),
            "aac".into(),
            "-b:a".into(),
            "192k".into(),
        ]),
        (false, false) => ff_args.push("-an".into()),
    }

    ff_args.extend([
        "-c:v".into(),
        "libx264".into(),
        "-preset".into(),
        "veryfast".into(),
        "-crf".into(),
        opts.crf.to_string(),
    ]);
    if rate > (opts.fps as f64) * 1.1 {
        ff_args.extend(["-vf".into(), format!("fps={}", opts.fps)]);
    }
    ff_args.extend(["-y".into(), opts.output.clone()]);
    ff_args
}

pub fn run_portal(args: &[String]) -> ! {
    let opts = parse_portal_args(args);
    let marker_path = format!("{}.capturing", opts.output);
    let _ = fs::remove_file(&marker_path);

    unsafe {
        signal(SIGINT, handle_stop as *const () as usize);
        signal(SIGTERM, handle_stop as *const () as usize);
    }

    let dbus = match LibDbus::load() {
        Some(d) => d,
        None => std::process::exit(127),
    };

    let pid = std::process::id();
    let sess = unsafe {
        open_screencast_session(&dbus, pid, opts.cursor_yes, opts.persist, &STOPPING)
    };

    if STOPPING.load(Ordering::Relaxed) {
        if let Some(fd) = sess.conn_fd {
            unsafe { close(fd) };
        }
        unsafe { dbus.close_session(sess.conn, &sess.session) };
        eprintln!("Stopped before capture started");
        std::process::exit(1);
    }

    // Build gst-launch-1.0 pipeline
    let mut gst_args: Vec<String> = vec!["-q".into(), "pipewiresrc".into()];
    if let Some(fd) = sess.conn_fd {
        gst_args.push(format!("fd={}", fd));
    }
    gst_args.push(format!("target-object={}", sess.stream_id));
    gst_args.extend(
        ["!", "videoconvert", "!", "video/x-raw,format=I420", "!", "fdsink"]
            .iter()
            .map(|s| s.to_string()),
    );

    let mut gst_cmd = Command::new("gst-launch-1.0");
    gst_cmd.args(&gst_args).stdout(Stdio::piped());
    unsafe {
        gst_cmd.pre_exec(|| {
            signal(SIGINT, SIG_DFL);
            signal(SIGTERM, SIG_DFL);
            Ok(())
        });
    }
    let mut gst = match gst_cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            if let Some(fd) = sess.conn_fd {
                unsafe { close(fd) };
            }
            unsafe { dbus.close_session(sess.conn, &sess.session) };
            eprintln!("Could not start gst: {}", e);
            std::process::exit(1);
        }
    };
    if let Some(fd) = sess.conn_fd {
        unsafe { close(fd) };
    }

    let mut gst_out = gst.stdout.take().unwrap();
    let mut poller = FdPoller::new(gst_out.as_raw_fd());
    let frame_bytes = (sess.width as usize) * (sess.height as usize) * 3 / 2;
    let mut buf = vec![0u8; CHUNK];
    let mut head: Vec<u8> = Vec::new();

    // Probe head of stream for real damage-driven frame rate
    let t0 = Instant::now();
    loop {
        if STOPPING.load(Ordering::Relaxed) {
            break;
        }
        let el = t0.elapsed();
        let have_frame = head.len() >= frame_bytes;
        if have_frame && el.as_secs_f64() >= RATE_PROBE_SECS {
            break;
        }
        if !have_frame && el >= NO_FRAME_LIMIT {
            break;
        }
        if !poller.wait_readable(200) {
            if gst.try_wait().ok().flatten().is_some() {
                break;
            }
            continue;
        }
        match gst_out.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => head.extend_from_slice(&buf[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
        if head.len() >= MAX_PROBE_BYTES {
            break;
        }
    }

    let elapsed = t0.elapsed().as_secs_f64().max(0.001);
    if head.len() < frame_bytes {
        stop_child(&mut gst, SIGTERM, Duration::from_secs(10));
        unsafe { dbus.close_session(sess.conn, &sess.session) };
        eprintln!("Screen share produced no frames in {:.1}s", elapsed);
        std::process::exit(1);
    }

    let rate = (head.len() as f64 / frame_bytes as f64 / elapsed).clamp(0.5, 240.0);
    let ff_args = build_ffmpeg_args(&opts, sess.width, sess.height, rate);

    let ff_err_path = format!("{}.ffmpeg.err", opts.output);
    let err_out = match File::create(&ff_err_path) {
        Ok(f) => Stdio::from(f),
        Err(_) => Stdio::null(),
    };

    let mut ff_cmd = Command::new("ffmpeg");
    ff_cmd
        .args(&ff_args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(err_out);
    unsafe {
        ff_cmd.pre_exec(|| {
            signal(SIGINT, SIG_DFL);
            signal(SIGTERM, SIG_DFL);
            Ok(())
        });
    }
    let mut ff = match ff_cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            let _ = fs::remove_file(&ff_err_path);
            stop_child(&mut gst, SIGTERM, Duration::from_secs(10));
            unsafe { dbus.close_session(sess.conn, &sess.session) };
            eprintln!("Could not start ffmpeg: {}", e);
            std::process::exit(1);
        }
    };
    let mut ff_in = ff.stdin.take();

    let _ = fs::write(&marker_path, format!("{}\n", pid));
    println!("capture-started");
    let _ = std::io::stdout().flush();
    eprintln!(
        "source {:.2} fps at {}x{}, recording at {} fps",
        rate, sess.width, sess.height, opts.fps
    );

    // Stream frame-aligned I420 into ffmpeg using a read-indexed queue
    let mut queue = FrameQueue::from_vec(head);
    let mut ff_died = false;
    loop {
        let ok = ff_in
            .as_mut()
            .is_some_and(|w| queue.write_whole_frames(frame_bytes, w));
        if !ok {
            ff_died = true;
            break;
        }
        if STOPPING.load(Ordering::Relaxed) {
            break;
        }
        if ff.try_wait().ok().flatten().is_some() {
            ff_died = true;
            break;
        }
        if !poller.wait_readable(200) {
            if gst.try_wait().ok().flatten().is_some() {
                break;
            }
            continue;
        }
        match gst_out.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => queue.extend_from_slice(&buf[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }

    stop_child(&mut gst, SIGTERM, Duration::from_secs(10));
    drop(ff_in.take());
    stop_child(&mut ff, SIGINT, Duration::from_secs(20));
    let _ = fs::remove_file(&marker_path);
    unsafe { dbus.close_session(sess.conn, &sess.session) };

    let mut code = 0;
    let valid_out = fs::metadata(&opts.output)
        .map(|m| m.len() > 0)
        .unwrap_or(false);
    if ff_died || !valid_out {
        code = 1;
        let err = fs::read_to_string(&ff_err_path).unwrap_or_default();
        let err = err.trim();
        if !err.is_empty() {
            eprintln!("ffmpeg failed: {}", err.chars().take(500).collect::<String>());
        }
    }
    let _ = fs::remove_file(&ff_err_path);
    std::process::exit(code);
}
