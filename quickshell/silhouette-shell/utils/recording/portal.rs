use std::env;
use std::ffi::{c_char, c_int, c_uint, c_void, CStr, CString};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::sleep;
use std::time::{Duration, Instant};

const RTLD_LAZY: c_int = 1;
const DBUS_BUS_SESSION: c_int = 0;

const DBUS_TYPE_BOOLEAN: c_int = b'b' as c_int;
const DBUS_TYPE_INT32: c_int = b'i' as c_int;
const DBUS_TYPE_UINT32: c_int = b'u' as c_int;
const DBUS_TYPE_STRING: c_int = b's' as c_int;
const DBUS_TYPE_OBJECT_PATH: c_int = b'o' as c_int;
const DBUS_TYPE_ARRAY: c_int = b'a' as c_int;
const DBUS_TYPE_VARIANT: c_int = b'v' as c_int;
const DBUS_TYPE_STRUCT: c_int = b'r' as c_int;
const DBUS_TYPE_DICT_ENTRY: c_int = b'e' as c_int;
const DBUS_TYPE_UNIX_FD: c_int = b'h' as c_int;

const F_SETFD: c_int = 2;
const SIGINT: c_int = 2;
const SIGTERM: c_int = 15;
const SIG_DFL: usize = 0;
const CHUNK: usize = 1 << 18;
const PICKER_TIMEOUT: Duration = Duration::from_secs(180);
const NO_FRAME_LIMIT: Duration = Duration::from_secs(30);
const RATE_PROBE_SECS: f64 = 2.0;
const MAX_PROBE_BYTES: usize = 64 << 20;

static STOPPING: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_stop(_sig: c_int) {
    STOPPING.store(true, Ordering::SeqCst);
}

#[repr(C)]
struct DBusError {
    name: *const c_char,
    message: *const c_char,
    dummy: c_uint,
    padding1: *mut c_void,
}

impl Default for DBusError {
    fn default() -> Self {
        Self {
            name: ptr::null(),
            message: ptr::null(),
            dummy: 0,
            padding1: ptr::null_mut(),
        }
    }
}

#[repr(C)]
struct DBusMessageIter {
    dummy1: *mut c_void,
    dummy2: *mut c_void,
    dummy3: u32,
    dummy4: c_int,
    dummy5: c_int,
    dummy6: c_int,
    dummy7: c_int,
    dummy8: c_int,
    dummy9: c_int,
    dummy10: c_int,
    dummy11: c_int,
    pad1: c_int,
    pad2: *mut c_void,
    pad3: *mut c_void,
}

impl Default for DBusMessageIter {
    fn default() -> Self {
        Self {
            dummy1: ptr::null_mut(),
            dummy2: ptr::null_mut(),
            dummy3: 0,
            dummy4: 0,
            dummy5: 0,
            dummy6: 0,
            dummy7: 0,
            dummy8: 0,
            dummy9: 0,
            dummy10: 0,
            dummy11: 0,
            pad1: 0,
            pad2: ptr::null_mut(),
            pad3: ptr::null_mut(),
        }
    }
}

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    fn close(fd: c_int) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn signal(sig: c_int, handler: usize) -> usize;
}

type ErrorInitFn = unsafe extern "C" fn(*mut DBusError);
type ErrorFreeFn = unsafe extern "C" fn(*mut DBusError);
type ErrorIsSetFn = unsafe extern "C" fn(*const DBusError) -> u32;
type BusGetFn = unsafe extern "C" fn(c_int, *mut DBusError) -> *mut c_void;
type BusAddMatchFn = unsafe extern "C" fn(*mut c_void, *const c_char, *mut DBusError);
type ConnFlushFn = unsafe extern "C" fn(*mut c_void);
type ConnSendBlockFn =
    unsafe extern "C" fn(*mut c_void, *mut c_void, c_int, *mut DBusError) -> *mut c_void;
type ConnReadWriteFn = unsafe extern "C" fn(*mut c_void, c_int) -> u32;
type ConnPopMsgFn = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
type MsgNewCallFn = unsafe extern "C" fn(
    *const c_char,
    *const c_char,
    *const c_char,
    *const c_char,
) -> *mut c_void;
type MsgIsSignalFn = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> u32;
type MsgGetPathFn = unsafe extern "C" fn(*mut c_void) -> *const c_char;
type MsgUnrefFn = unsafe extern "C" fn(*mut c_void);
type IterInitFn = unsafe extern "C" fn(*mut c_void, *mut DBusMessageIter) -> u32;
type IterInitAppendFn = unsafe extern "C" fn(*mut c_void, *mut DBusMessageIter);
type IterAppendBasicFn = unsafe extern "C" fn(*mut DBusMessageIter, c_int, *const c_void) -> u32;
type IterOpenContFn =
    unsafe extern "C" fn(*mut DBusMessageIter, c_int, *const c_char, *mut DBusMessageIter) -> u32;
type IterCloseContFn = unsafe extern "C" fn(*mut DBusMessageIter, *mut DBusMessageIter) -> u32;
type IterGetArgTypeFn = unsafe extern "C" fn(*mut DBusMessageIter) -> c_int;
type IterNextFn = unsafe extern "C" fn(*mut DBusMessageIter) -> u32;
type IterRecurseFn = unsafe extern "C" fn(*mut DBusMessageIter, *mut DBusMessageIter);
type IterGetBasicFn = unsafe extern "C" fn(*mut DBusMessageIter, *mut c_void);

struct LibDbus {
    lib: *mut c_void,
    err_init: ErrorInitFn,
    err_free: ErrorFreeFn,
    err_is_set: ErrorIsSetFn,
    bus_get: BusGetFn,
    bus_add_match: BusAddMatchFn,
    conn_flush: ConnFlushFn,
    conn_send_block: ConnSendBlockFn,
    conn_rw: ConnReadWriteFn,
    conn_pop: ConnPopMsgFn,
    msg_new_call: MsgNewCallFn,
    msg_is_sig: MsgIsSignalFn,
    msg_get_path: MsgGetPathFn,
    msg_unref: MsgUnrefFn,
    iter_init: IterInitFn,
    iter_init_append: IterInitAppendFn,
    iter_append_basic: IterAppendBasicFn,
    iter_open_cont: IterOpenContFn,
    iter_close_cont: IterCloseContFn,
    iter_type: IterGetArgTypeFn,
    iter_next: IterNextFn,
    iter_recurse: IterRecurseFn,
    iter_basic: IterGetBasicFn,
}

unsafe fn sym<T>(lib: *mut c_void, name: &[u8]) -> Option<T> {
    let p = dlsym(lib, name.as_ptr() as *const c_char);
    if p.is_null() {
        None
    } else {
        Some(std::mem::transmute_copy(&p))
    }
}

impl LibDbus {
    fn load() -> Option<Self> {
        unsafe {
            let lib = dlopen(b"libdbus-1.so.3\0".as_ptr() as *const c_char, RTLD_LAZY);
            if lib.is_null() {
                return None;
            }
            let me = Self {
                lib,
                err_init: sym(lib, b"dbus_error_init\0")?,
                err_free: sym(lib, b"dbus_error_free\0")?,
                err_is_set: sym(lib, b"dbus_error_is_set\0")?,
                bus_get: sym(lib, b"dbus_bus_get\0")?,
                bus_add_match: sym(lib, b"dbus_bus_add_match\0")?,
                conn_flush: sym(lib, b"dbus_connection_flush\0")?,
                conn_send_block: sym(lib, b"dbus_connection_send_with_reply_and_block\0")?,
                conn_rw: sym(lib, b"dbus_connection_read_write\0")?,
                conn_pop: sym(lib, b"dbus_connection_pop_message\0")?,
                msg_new_call: sym(lib, b"dbus_message_new_method_call\0")?,
                msg_is_sig: sym(lib, b"dbus_message_is_signal\0")?,
                msg_get_path: sym(lib, b"dbus_message_get_path\0")?,
                msg_unref: sym(lib, b"dbus_message_unref\0")?,
                iter_init: sym(lib, b"dbus_message_iter_init\0")?,
                iter_init_append: sym(lib, b"dbus_message_iter_init_append\0")?,
                iter_append_basic: sym(lib, b"dbus_message_iter_append_basic\0")?,
                iter_open_cont: sym(lib, b"dbus_message_iter_open_container\0")?,
                iter_close_cont: sym(lib, b"dbus_message_iter_close_container\0")?,
                iter_type: sym(lib, b"dbus_message_iter_get_arg_type\0")?,
                iter_next: sym(lib, b"dbus_message_iter_next\0")?,
                iter_recurse: sym(lib, b"dbus_message_iter_recurse\0")?,
                iter_basic: sym(lib, b"dbus_message_iter_get_basic\0")?,
            };
            Some(me)
        }
    }

    unsafe fn append_dict_str(&self, dict: &mut DBusMessageIter, key: &str, val: &str) {
        let ck = CString::new(key).unwrap();
        let cv = CString::new(val).unwrap();
        let mut entry = DBusMessageIter::default();
        let mut var = DBusMessageIter::default();
        (self.iter_open_cont)(dict, DBUS_TYPE_DICT_ENTRY, ptr::null(), &mut entry);
        let kp = ck.as_ptr();
        (self.iter_append_basic)(&mut entry, DBUS_TYPE_STRING, &kp as *const *const c_char as *const c_void);
        (self.iter_open_cont)(&mut entry, DBUS_TYPE_VARIANT, b"s\0".as_ptr() as *const c_char, &mut var);
        let vp = cv.as_ptr();
        (self.iter_append_basic)(&mut var, DBUS_TYPE_STRING, &vp as *const *const c_char as *const c_void);
        (self.iter_close_cont)(&mut entry, &mut var);
        (self.iter_close_cont)(dict, &mut entry);
    }

    unsafe fn append_dict_u32(&self, dict: &mut DBusMessageIter, key: &str, val: u32) {
        let ck = CString::new(key).unwrap();
        let mut entry = DBusMessageIter::default();
        let mut var = DBusMessageIter::default();
        (self.iter_open_cont)(dict, DBUS_TYPE_DICT_ENTRY, ptr::null(), &mut entry);
        let kp = ck.as_ptr();
        (self.iter_append_basic)(&mut entry, DBUS_TYPE_STRING, &kp as *const *const c_char as *const c_void);
        (self.iter_open_cont)(&mut entry, DBUS_TYPE_VARIANT, b"u\0".as_ptr() as *const c_char, &mut var);
        (self.iter_append_basic)(&mut var, DBUS_TYPE_UINT32, &val as *const u32 as *const c_void);
        (self.iter_close_cont)(&mut entry, &mut var);
        (self.iter_close_cont)(dict, &mut entry);
    }

    unsafe fn append_dict_bool(&self, dict: &mut DBusMessageIter, key: &str, val: bool) {
        let ck = CString::new(key).unwrap();
        let mut entry = DBusMessageIter::default();
        let mut var = DBusMessageIter::default();
        (self.iter_open_cont)(dict, DBUS_TYPE_DICT_ENTRY, ptr::null(), &mut entry);
        let kp = ck.as_ptr();
        (self.iter_append_basic)(&mut entry, DBUS_TYPE_STRING, &kp as *const *const c_char as *const c_void);
        (self.iter_open_cont)(&mut entry, DBUS_TYPE_VARIANT, b"b\0".as_ptr() as *const c_char, &mut var);
        let bval: u32 = if val { 1 } else { 0 };
        (self.iter_append_basic)(&mut var, DBUS_TYPE_BOOLEAN, &bval as *const u32 as *const c_void);
        (self.iter_close_cont)(&mut entry, &mut var);
        (self.iter_close_cont)(dict, &mut entry);
    }

    unsafe fn read_str(&self, it: &mut DBusMessageIter) -> Option<String> {
        let ty = (self.iter_type)(it);
        if ty == DBUS_TYPE_STRING || ty == DBUS_TYPE_OBJECT_PATH {
            let mut p: *const c_char = ptr::null();
            (self.iter_basic)(it, &mut p as *mut *const c_char as *mut c_void);
            if !p.is_null() {
                return Some(CStr::from_ptr(p).to_string_lossy().into_owned());
            }
        }
        None
    }

    unsafe fn wait_response(
        &self,
        conn: *mut c_void,
        req_path: &str,
    ) -> Option<(u32, *mut c_void)> {
        let t0 = Instant::now();
        let iface = b"org.freedesktop.portal.Request\0";
        let member = b"Response\0";
        while t0.elapsed() < PICKER_TIMEOUT {
            if STOPPING.load(Ordering::SeqCst) {
                return None;
            }
            if (self.conn_rw)(conn, 200) == 0 {
                return None;
            }
            loop {
                let msg = (self.conn_pop)(conn);
                if msg.is_null() {
                    break;
                }
                if (self.msg_is_sig)(msg, iface.as_ptr() as *const c_char, member.as_ptr() as *const c_char) != 0 {
                    let p = (self.msg_get_path)(msg);
                    if !p.is_null() && CStr::from_ptr(p).to_string_lossy() == req_path {
                        let mut it = DBusMessageIter::default();
                        let mut code: u32 = 2;
                        if (self.iter_init)(msg, &mut it) != 0 && (self.iter_type)(&mut it) == DBUS_TYPE_UINT32 {
                            (self.iter_basic)(&mut it, &mut code as *mut u32 as *mut c_void);
                        }
                        return Some((code, msg));
                    }
                }
                (self.msg_unref)(msg);
            }
        }
        None
    }

    unsafe fn dict_lookup_str(&self, msg: *mut c_void, target_key: &str) -> Option<String> {
        let mut it = DBusMessageIter::default();
        if (self.iter_init)(msg, &mut it) == 0 {
            return None;
        }
        if (self.iter_next)(&mut it) == 0 || (self.iter_type)(&mut it) != DBUS_TYPE_ARRAY {
            return None;
        }
        let mut arr = DBusMessageIter::default();
        (self.iter_recurse)(&mut it, &mut arr);
        while (self.iter_type)(&mut arr) == DBUS_TYPE_DICT_ENTRY {
            let mut entry = DBusMessageIter::default();
            (self.iter_recurse)(&mut arr, &mut entry);
            if let Some(k) = self.read_str(&mut entry) {
                if k == target_key && (self.iter_next)(&mut entry) != 0 && (self.iter_type)(&mut entry) == DBUS_TYPE_VARIANT {
                    let mut var = DBusMessageIter::default();
                    (self.iter_recurse)(&mut entry, &mut var);
                    return self.read_str(&mut var);
                }
            }
            (self.iter_next)(&mut arr);
        }
        None
    }

    unsafe fn parse_first_stream(&self, msg: *mut c_void) -> Option<(u32, i32, i32)> {
        let mut it = DBusMessageIter::default();
        if (self.iter_init)(msg, &mut it) == 0 || (self.iter_next)(&mut it) == 0 {
            return None;
        }
        if (self.iter_type)(&mut it) != DBUS_TYPE_ARRAY {
            return None;
        }
        let mut arr = DBusMessageIter::default();
        (self.iter_recurse)(&mut it, &mut arr);
        while (self.iter_type)(&mut arr) == DBUS_TYPE_DICT_ENTRY {
            let mut entry = DBusMessageIter::default();
            (self.iter_recurse)(&mut arr, &mut entry);
            if let Some(k) = self.read_str(&mut entry) {
                if k == "streams" && (self.iter_next)(&mut entry) != 0 && (self.iter_type)(&mut entry) == DBUS_TYPE_VARIANT {
                    let mut var = DBusMessageIter::default();
                    (self.iter_recurse)(&mut entry, &mut var);
                    if (self.iter_type)(&mut var) != DBUS_TYPE_ARRAY {
                        return None;
                    }
                    let mut streams = DBusMessageIter::default();
                    (self.iter_recurse)(&mut var, &mut streams);
                    if (self.iter_type)(&mut streams) != DBUS_TYPE_STRUCT {
                        return None;
                    }
                    let mut st = DBusMessageIter::default();
                    (self.iter_recurse)(&mut streams, &mut st);
                    let mut node_id: u32 = 0;
                    if (self.iter_type)(&mut st) != DBUS_TYPE_UINT32 {
                        return None;
                    }
                    (self.iter_basic)(&mut st, &mut node_id as *mut u32 as *mut c_void);
                    if (self.iter_next)(&mut st) == 0 || (self.iter_type)(&mut st) != DBUS_TYPE_ARRAY {
                        return None;
                    }
                    let mut props = DBusMessageIter::default();
                    (self.iter_recurse)(&mut st, &mut props);
                    let mut w: i32 = 0;
                    let mut h: i32 = 0;
                    while (self.iter_type)(&mut props) == DBUS_TYPE_DICT_ENTRY {
                        let mut pe = DBusMessageIter::default();
                        (self.iter_recurse)(&mut props, &mut pe);
                        if let Some(pk) = self.read_str(&mut pe) {
                            if pk == "size" && (self.iter_next)(&mut pe) != 0 && (self.iter_type)(&mut pe) == DBUS_TYPE_VARIANT {
                                let mut pv = DBusMessageIter::default();
                                (self.iter_recurse)(&mut pe, &mut pv);
                                if (self.iter_type)(&mut pv) == DBUS_TYPE_STRUCT {
                                    let mut sz = DBusMessageIter::default();
                                    (self.iter_recurse)(&mut pv, &mut sz);
                                    let t1 = (self.iter_type)(&mut sz);
                                    if t1 == DBUS_TYPE_INT32 || t1 == DBUS_TYPE_UINT32 {
                                        (self.iter_basic)(&mut sz, &mut w as *mut i32 as *mut c_void);
                                    }
                                    if (self.iter_next)(&mut sz) != 0 {
                                        let t2 = (self.iter_type)(&mut sz);
                                        if t2 == DBUS_TYPE_INT32 || t2 == DBUS_TYPE_UINT32 {
                                            (self.iter_basic)(&mut sz, &mut h as *mut i32 as *mut c_void);
                                        }
                                    }
                                }
                            }
                        }
                        (self.iter_next)(&mut props);
                    }
                    return Some((node_id, w, h));
                }
            }
            (self.iter_next)(&mut arr);
        }
        None
    }

    unsafe fn close_session(&self, conn: *mut c_void, session: &str) {
        let c_sess = match CString::new(session) {
            Ok(s) => s,
            Err(_) => return,
        };
        let msg = (self.msg_new_call)(
            b"org.freedesktop.portal.Desktop\0".as_ptr() as *const c_char,
            b"/org/freedesktop/portal/desktop\0".as_ptr() as *const c_char,
            b"org.freedesktop.portal.ScreenCast\0".as_ptr() as *const c_char,
            b"CloseSession\0".as_ptr() as *const c_char,
        );
        if msg.is_null() {
            return;
        }
        let mut it = DBusMessageIter::default();
        (self.iter_init_append)(msg, &mut it);
        let sp = c_sess.as_ptr();
        (self.iter_append_basic)(&mut it, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
        let mut err = DBusError::default();
        (self.err_init)(&mut err);
        let reply = (self.conn_send_block)(conn, msg, 3000, &mut err);
        if !reply.is_null() {
            (self.msg_unref)(reply);
        }
        (self.err_free)(&mut err);
        (self.msg_unref)(msg);
    }
}

impl Drop for LibDbus {
    fn drop(&mut self) {
        unsafe {
            dlclose(self.lib);
        }
    }
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

fn restore_token_path() -> PathBuf {
    let base = env::var("XDG_CACHE_HOME")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var("HOME").unwrap_or_else(|_| "/tmp".to_string())).join(".cache")
        });
    base.join("silhouette").join("rec-restore-token")
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
    let mut tok_n = 0u32;
    let mut next_tok = || {
        tok_n += 1;
        format!("quickshell_{}_{}", pid, tok_n)
    };

    let (conn, session, stream_id, width, height, conn_fd) = unsafe {
        let mut err = DBusError::default();
        (dbus.err_init)(&mut err);
        let conn = (dbus.bus_get)(DBUS_BUS_SESSION, &mut err);
        if conn.is_null() || (dbus.err_is_set)(&err) != 0 {
            (dbus.err_free)(&mut err);
            eprintln!("Screen share portal error: cannot connect to session D-Bus");
            std::process::exit(1);
        }

        let rule = b"type='signal',interface='org.freedesktop.portal.Request',member='Response'\0";
        (dbus.bus_add_match)(conn, rule.as_ptr() as *const c_char, &mut err);
        if (dbus.err_is_set)(&err) != 0 {
            (dbus.err_free)(&mut err);
            eprintln!("Screen share portal error: cannot subscribe to Request.Response");
            std::process::exit(1);
        }
        (dbus.conn_flush)(conn);

        let dest = b"org.freedesktop.portal.Desktop\0".as_ptr() as *const c_char;
        let path = b"/org/freedesktop/portal/desktop\0".as_ptr() as *const c_char;
        let sc_iface = b"org.freedesktop.portal.ScreenCast\0".as_ptr() as *const c_char;
        let pw_iface = b"org.freedesktop.portal.PipeWire\0".as_ptr() as *const c_char;

        // 1. CreateSession
        let call1 = (dbus.msg_new_call)(dest, path, sc_iface, b"CreateSession\0".as_ptr() as *const c_char);
        let mut it1 = DBusMessageIter::default();
        let mut d1 = DBusMessageIter::default();
        (dbus.iter_init_append)(call1, &mut it1);
        (dbus.iter_open_cont)(&mut it1, DBUS_TYPE_ARRAY, b"{sv}\0".as_ptr() as *const c_char, &mut d1);
        dbus.append_dict_str(&mut d1, "handle_token", &next_tok());
        dbus.append_dict_str(&mut d1, "session_handle_token", &next_tok());
        (dbus.iter_close_cont)(&mut it1, &mut d1);
        let rep1 = (dbus.conn_send_block)(conn, call1, 30_000, &mut err);
        (dbus.msg_unref)(call1);
        if rep1.is_null() || (dbus.err_is_set)(&err) != 0 {
            (dbus.err_free)(&mut err);
            eprintln!("Screen share session could not be created");
            std::process::exit(1);
        }
        let mut rit1 = DBusMessageIter::default();
        let req1 = if (dbus.iter_init)(rep1, &mut rit1) != 0 {
            dbus.read_str(&mut rit1).unwrap_or_default()
        } else {
            String::new()
        };
        (dbus.msg_unref)(rep1);

        let (code1, sig1) = match dbus.wait_response(conn, &req1) {
            Some(r) => r,
            None => {
                eprintln!("Screen share session timed out or stopped");
                std::process::exit(1);
            }
        };
        if code1 != 0 {
            (dbus.msg_unref)(sig1);
            eprintln!("Screen share session could not be created (portal error {})", code1);
            std::process::exit(1);
        }
        let session = match dbus.dict_lookup_str(sig1, "session_handle") {
            Some(s) if !s.is_empty() => s,
            _ => {
                (dbus.msg_unref)(sig1);
                eprintln!("Screen share session returned no session_handle");
                std::process::exit(1);
            }
        };
        (dbus.msg_unref)(sig1);

        // 2. SelectSources
        let c_sess = CString::new(session.as_str()).unwrap();
        let token_path = restore_token_path();
        let saved_token = fs::read_to_string(&token_path)
            .map(|s| s.trim().to_string())
            .unwrap_or_default();

        let call2 = (dbus.msg_new_call)(dest, path, sc_iface, b"SelectSources\0".as_ptr() as *const c_char);
        let mut it2 = DBusMessageIter::default();
        let mut d2 = DBusMessageIter::default();
        (dbus.iter_init_append)(call2, &mut it2);
        let sp = c_sess.as_ptr();
        (dbus.iter_append_basic)(&mut it2, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
        (dbus.iter_open_cont)(&mut it2, DBUS_TYPE_ARRAY, b"{sv}\0".as_ptr() as *const c_char, &mut d2);
        dbus.append_dict_str(&mut d2, "handle_token", &next_tok());
        dbus.append_dict_u32(&mut d2, "types", 1); // MONITOR
        dbus.append_dict_bool(&mut d2, "multiple", false);
        dbus.append_dict_u32(&mut d2, "cursor_mode", if opts.cursor_yes { 1 } else { 2 });
        dbus.append_dict_u32(&mut d2, "persist_mode", opts.persist);
        if !saved_token.is_empty() {
            dbus.append_dict_str(&mut d2, "restore_token", &saved_token);
        }
        (dbus.iter_close_cont)(&mut it2, &mut d2);
        let rep2 = (dbus.conn_send_block)(conn, call2, 210_000, &mut err);
        (dbus.msg_unref)(call2);
        if rep2.is_null() || (dbus.err_is_set)(&err) != 0 {
            (dbus.err_free)(&mut err);
            dbus.close_session(conn, &session);
            eprintln!("Screen share selection failed");
            std::process::exit(1);
        }
        let mut rit2 = DBusMessageIter::default();
        let req2 = if (dbus.iter_init)(rep2, &mut rit2) != 0 {
            dbus.read_str(&mut rit2).unwrap_or_default()
        } else {
            String::new()
        };
        (dbus.msg_unref)(rep2);

        let (code2, sig2) = match dbus.wait_response(conn, &req2) {
            Some(r) => r,
            None => {
                dbus.close_session(conn, &session);
                eprintln!("Screen share selection was cancelled");
                std::process::exit(1);
            }
        };
        if code2 != 0 {
            (dbus.msg_unref)(sig2);
            dbus.close_session(conn, &session);
            eprintln!("Screen share selection was cancelled");
            std::process::exit(1);
        }
        if let Some(issued) = dbus.dict_lookup_str(sig2, "restore_token") {
            if !issued.is_empty() && issued != saved_token {
                if let Some(parent) = token_path.parent() {
                    let _ = fs::create_dir_all(parent);
                }
                let _ = fs::write(&token_path, issued);
            }
        }
        (dbus.msg_unref)(sig2);

        // 3. Start
        let call3 = (dbus.msg_new_call)(dest, path, sc_iface, b"Start\0".as_ptr() as *const c_char);
        let mut it3 = DBusMessageIter::default();
        let mut d3 = DBusMessageIter::default();
        (dbus.iter_init_append)(call3, &mut it3);
        (dbus.iter_append_basic)(&mut it3, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
        let empty = b"\0".as_ptr() as *const c_char;
        (dbus.iter_append_basic)(&mut it3, DBUS_TYPE_STRING, &empty as *const *const c_char as *const c_void);
        (dbus.iter_open_cont)(&mut it3, DBUS_TYPE_ARRAY, b"{sv}\0".as_ptr() as *const c_char, &mut d3);
        dbus.append_dict_str(&mut d3, "handle_token", &next_tok());
        (dbus.iter_close_cont)(&mut it3, &mut d3);
        let rep3 = (dbus.conn_send_block)(conn, call3, 210_000, &mut err);
        (dbus.msg_unref)(call3);
        if rep3.is_null() || (dbus.err_is_set)(&err) != 0 {
            (dbus.err_free)(&mut err);
            dbus.close_session(conn, &session);
            eprintln!("Screen share start failed");
            std::process::exit(1);
        }
        let mut rit3 = DBusMessageIter::default();
        let req3 = if (dbus.iter_init)(rep3, &mut rit3) != 0 {
            dbus.read_str(&mut rit3).unwrap_or_default()
        } else {
            String::new()
        };
        (dbus.msg_unref)(rep3);

        let (code3, sig3) = match dbus.wait_response(conn, &req3) {
            Some(r) => r,
            None => {
                dbus.close_session(conn, &session);
                eprintln!("Screen share start was cancelled");
                std::process::exit(1);
            }
        };
        if code3 != 0 {
            (dbus.msg_unref)(sig3);
            dbus.close_session(conn, &session);
            eprintln!("Screen share start was cancelled");
            std::process::exit(1);
        }
        let (stream_id, width, height) = match dbus.parse_first_stream(sig3) {
            Some((id, w, h)) if w > 0 && h > 0 => (id, w, h),
            _ => {
                (dbus.msg_unref)(sig3);
                dbus.close_session(conn, &session);
                eprintln!("Screen share returned no usable stream");
                std::process::exit(1);
            }
        };
        (dbus.msg_unref)(sig3);

        // 4. OpenPipeWireRemote (optional; gtk portal omits it)
        let mut conn_fd: Option<c_int> = None;
        let call4 = (dbus.msg_new_call)(dest, path, pw_iface, b"OpenPipeWireRemote\0".as_ptr() as *const c_char);
        let mut it4 = DBusMessageIter::default();
        let mut d4 = DBusMessageIter::default();
        (dbus.iter_init_append)(call4, &mut it4);
        (dbus.iter_append_basic)(&mut it4, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
        (dbus.iter_open_cont)(&mut it4, DBUS_TYPE_ARRAY, b"{sv}\0".as_ptr() as *const c_char, &mut d4);
        (dbus.iter_close_cont)(&mut it4, &mut d4);
        let rep4 = (dbus.conn_send_block)(conn, call4, 10_000, &mut err);
        (dbus.msg_unref)(call4);
        if !rep4.is_null() && (dbus.err_is_set)(&err) == 0 {
            let mut rit4 = DBusMessageIter::default();
            if (dbus.iter_init)(rep4, &mut rit4) != 0 && (dbus.iter_type)(&mut rit4) == DBUS_TYPE_UNIX_FD {
                let mut fd: c_int = -1;
                (dbus.iter_basic)(&mut rit4, &mut fd as *mut c_int as *mut c_void);
                if fd >= 0 {
                    // Clear FD_CLOEXEC so gst-launch-1.0 inherits the PipeWire remote FD
                    let _ = fcntl(fd, F_SETFD, 0);
                    conn_fd = Some(fd);
                }
            }
            (dbus.msg_unref)(rep4);
        } else {
            (dbus.err_free)(&mut err);
        }

        (conn, session, stream_id, width, height, conn_fd)
    };

    if STOPPING.load(Ordering::SeqCst) {
        if let Some(fd) = conn_fd {
            unsafe { close(fd) };
        }
        unsafe { dbus.close_session(conn, &session) };
        eprintln!("Stopped before capture started");
        std::process::exit(1);
    }

    // Build gst-launch-1.0 pipeline
    let mut gst_args: Vec<String> = vec!["-q".into(), "pipewiresrc".into()];
    if let Some(fd) = conn_fd {
        gst_args.push(format!("fd={}", fd));
    }
    gst_args.push(format!("target-object={}", stream_id));
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
            if let Some(fd) = conn_fd {
                unsafe { close(fd) };
            }
            unsafe { dbus.close_session(conn, &session) };
            eprintln!("Could not start gst: {}", e);
            std::process::exit(1);
        }
    };
    if let Some(fd) = conn_fd {
        unsafe { close(fd) };
    }

    let mut gst_out = gst.stdout.take().unwrap();
    let src_fd = gst_out.as_raw_fd();
    let frame_bytes = (width as usize) * (height as usize) * 3 / 2;
    let mut buf = vec![0u8; CHUNK];
    let mut head: Vec<u8> = Vec::new();

    // Probe head of stream for real damage-driven frame rate
    let t0 = Instant::now();
    loop {
        if STOPPING.load(Ordering::SeqCst) {
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
        if !crate::wait_readable(src_fd, 200) {
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
        unsafe { dbus.close_session(conn, &session) };
        eprintln!("Screen share produced no frames in {:.1}s", elapsed);
        std::process::exit(1);
    }

    let rate = (head.len() as f64 / frame_bytes as f64 / elapsed).clamp(0.5, 240.0);
    let mut rate_str = format!("{:.3}", rate);
    while rate_str.ends_with('0') {
        rate_str.pop();
    }
    if rate_str.ends_with('.') {
        rate_str.pop();
    }

    // Build ffmpeg command
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
        rate_str,
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
            unsafe { dbus.close_session(conn, &session) };
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
        rate, width, height, opts.fps
    );

    // Stream frame-aligned I420 into ffmpeg
    let mut pending = head;
    let mut ff_died = false;
    loop {
        let whole = pending.len() - pending.len() % frame_bytes;
        if whole > 0 {
            let ok = ff_in
                .as_mut()
                .map_or(false, |w| w.write_all(&pending[..whole]).is_ok());
            if !ok {
                ff_died = true;
                break;
            }
            pending.drain(..whole);
        }
        if STOPPING.load(Ordering::SeqCst) {
            break;
        }
        if ff.try_wait().ok().flatten().is_some() {
            ff_died = true;
            break;
        }
        if !crate::wait_readable(src_fd, 200) {
            if gst.try_wait().ok().flatten().is_some() {
                break;
            }
            continue;
        }
        match gst_out.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => pending.extend_from_slice(&buf[..n]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }

    stop_child(&mut gst, SIGTERM, Duration::from_secs(10));
    drop(ff_in.take());
    stop_child(&mut ff, SIGINT, Duration::from_secs(20));
    let _ = fs::remove_file(&marker_path);
    unsafe { dbus.close_session(conn, &session) };

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
