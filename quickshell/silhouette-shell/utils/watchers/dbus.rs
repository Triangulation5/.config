use std::ffi::{c_char, c_int, c_uint, c_void};
use std::io::{self, Write};
use std::ptr;

const RTLD_LAZY: c_int = 1;
const DBUS_BUS_SYSTEM: c_int = 1;
const DBUS_TYPE_BOOLEAN: c_int = b'b' as c_int;
const DBUS_TYPE_INVALID: c_int = 0;

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

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

type ErrorInitFn = unsafe extern "C" fn(*mut DBusError);
type ErrorFreeFn = unsafe extern "C" fn(*mut DBusError);
type ErrorIsSetFn = unsafe extern "C" fn(*const DBusError) -> u32;
type BusGetFn = unsafe extern "C" fn(c_int, *mut DBusError) -> *mut c_void;
type BusAddMatchFn = unsafe extern "C" fn(*mut c_void, *const c_char, *mut DBusError);
type ConnFlushFn = unsafe extern "C" fn(*mut c_void);
type ConnReadWriteFn = unsafe extern "C" fn(*mut c_void, c_int) -> u32;
type ConnPopMsgFn = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
type MsgIsSignalFn = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> u32;
type MsgUnrefFn = unsafe extern "C" fn(*mut c_void);
type MsgIterInitFn = unsafe extern "C" fn(*mut c_void, *mut DBusMessageIter) -> u32;
type MsgIterGetArgTypeFn = unsafe extern "C" fn(*mut DBusMessageIter) -> c_int;
type MsgIterGetBasicFn = unsafe extern "C" fn(*mut DBusMessageIter, *mut c_void);

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

unsafe fn load_sym<T>(lib: *mut c_void, name: &[u8]) -> Option<T> {
    let p = dlsym(lib, name.as_ptr() as *const c_char);
    if p.is_null() {
        None
    } else {
        Some(std::mem::transmute_copy(&p))
    }
}

/// Native logind D-Bus signal monitor via `libdbus-1.so.3`.
/// Emits `LOCK`, `SUSPEND`, or `RESUME` lines on stdout.
/// Exits 127 if libdbus-1 is unavailable so QML falls back to `dbus-monitor`.
pub fn cmd_logind_watch() {
    unsafe {
        let lib = dlopen(c"libdbus-1.so.3".as_ptr(), RTLD_LAZY);
        if lib.is_null() {
            std::process::exit(127);
        }

        let err_init: ErrorInitFn = match load_sym(lib, b"dbus_error_init\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let err_free: ErrorFreeFn = match load_sym(lib, b"dbus_error_free\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let err_is_set: ErrorIsSetFn = match load_sym(lib, b"dbus_error_is_set\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let bus_get: BusGetFn = match load_sym(lib, b"dbus_bus_get\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let bus_add_match: BusAddMatchFn = match load_sym(lib, b"dbus_bus_add_match\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let conn_flush: ConnFlushFn = match load_sym(lib, b"dbus_connection_flush\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let conn_rw: ConnReadWriteFn = match load_sym(lib, b"dbus_connection_read_write\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let conn_pop: ConnPopMsgFn = match load_sym(lib, b"dbus_connection_pop_message\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let msg_is_sig: MsgIsSignalFn = match load_sym(lib, b"dbus_message_is_signal\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let msg_unref: MsgUnrefFn = match load_sym(lib, b"dbus_message_unref\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let iter_init: MsgIterInitFn = match load_sym(lib, b"dbus_message_iter_init\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };
        let iter_type: MsgIterGetArgTypeFn =
            match load_sym(lib, b"dbus_message_iter_get_arg_type\0") {
                Some(f) => f,
                None => {
                    dlclose(lib);
                    std::process::exit(127);
                }
            };
        let iter_basic: MsgIterGetBasicFn = match load_sym(lib, b"dbus_message_iter_get_basic\0") {
            Some(f) => f,
            None => {
                dlclose(lib);
                std::process::exit(127);
            }
        };

        let mut err = DBusError::default();
        err_init(&mut err);
        let conn = bus_get(DBUS_BUS_SYSTEM, &mut err);
        if conn.is_null() || err_is_set(&err) != 0 {
            err_free(&mut err);
            dlclose(lib);
            std::process::exit(1);
        }

        let rule_lock = b"type='signal',interface='org.freedesktop.login1.Session',member='Lock'\0";
        let rule_sleep = b"type='signal',path='/org/freedesktop/login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'\0";

        bus_add_match(conn, rule_lock.as_ptr() as *const c_char, &mut err);
        if err_is_set(&err) != 0 {
            err_free(&mut err);
            dlclose(lib);
            std::process::exit(1);
        }
        bus_add_match(conn, rule_sleep.as_ptr() as *const c_char, &mut err);
        if err_is_set(&err) != 0 {
            err_free(&mut err);
            dlclose(lib);
            std::process::exit(1);
        }
        conn_flush(conn);

        let stdout = io::stdout();
        let mut out = stdout.lock();

        let iface_sess = b"org.freedesktop.login1.Session\0";
        let mem_lock = b"Lock\0";
        let iface_mgr = b"org.freedesktop.login1.Manager\0";
        let mem_sleep = b"PrepareForSleep\0";

        while conn_rw(conn, 1000) != 0 {
            loop {
                let msg = conn_pop(conn);
                if msg.is_null() {
                    break;
                }
                if msg_is_sig(
                    msg,
                    iface_sess.as_ptr() as *const c_char,
                    mem_lock.as_ptr() as *const c_char,
                ) != 0
                {
                    if writeln!(out, "LOCK").is_err() || out.flush().is_err() {
                        msg_unref(msg);
                        dlclose(lib);
                        return;
                    }
                } else if msg_is_sig(
                    msg,
                    iface_mgr.as_ptr() as *const c_char,
                    mem_sleep.as_ptr() as *const c_char,
                ) != 0
                {
                    let mut it = DBusMessageIter::default();
                    if iter_init(msg, &mut it) != 0 && iter_type(&mut it) == DBUS_TYPE_BOOLEAN {
                        let mut val: u32 = 0;
                        iter_basic(&mut it, &mut val as *mut u32 as *mut c_void);
                        let line = if val != 0 { "SUSPEND" } else { "RESUME" };
                        if writeln!(out, "{}", line).is_err() || out.flush().is_err() {
                            msg_unref(msg);
                            dlclose(lib);
                            return;
                        }
                    } else if iter_type(&mut it) == DBUS_TYPE_INVALID {
                        // Ignore malformed signal with no args
                    }
                }
                msg_unref(msg);
            }
        }

        dlclose(lib);
    }
}
