use std::ffi::{c_char, c_int, c_uint, c_void, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

const RTLD_LAZY: c_int = 1;
pub(crate) const DBUS_BUS_SESSION: c_int = 0;

pub(crate) const DBUS_TYPE_BOOLEAN: c_int = b'b' as c_int;
pub(crate) const DBUS_TYPE_INT32: c_int = b'i' as c_int;
pub(crate) const DBUS_TYPE_UINT32: c_int = b'u' as c_int;
pub(crate) const DBUS_TYPE_STRING: c_int = b's' as c_int;
pub(crate) const DBUS_TYPE_OBJECT_PATH: c_int = b'o' as c_int;
pub(crate) const DBUS_TYPE_ARRAY: c_int = b'a' as c_int;
pub(crate) const DBUS_TYPE_VARIANT: c_int = b'v' as c_int;
pub(crate) const DBUS_TYPE_STRUCT: c_int = b'r' as c_int;
pub(crate) const DBUS_TYPE_DICT_ENTRY: c_int = b'e' as c_int;
pub(crate) const DBUS_TYPE_UNIX_FD: c_int = b'h' as c_int;

const PICKER_TIMEOUT: Duration = Duration::from_secs(180);

#[repr(C)]
pub(crate) struct DBusError {
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
pub(crate) struct DBusMessageIter {
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
}

pub(crate) type ErrorInitFn = unsafe extern "C" fn(*mut DBusError);
pub(crate) type ErrorFreeFn = unsafe extern "C" fn(*mut DBusError);
pub(crate) type ErrorIsSetFn = unsafe extern "C" fn(*const DBusError) -> u32;
pub(crate) type BusGetFn = unsafe extern "C" fn(c_int, *mut DBusError) -> *mut c_void;
pub(crate) type BusAddMatchFn = unsafe extern "C" fn(*mut c_void, *const c_char, *mut DBusError);
pub(crate) type ConnFlushFn = unsafe extern "C" fn(*mut c_void);
pub(crate) type ConnSendBlockFn =
    unsafe extern "C" fn(*mut c_void, *mut c_void, c_int, *mut DBusError) -> *mut c_void;
pub(crate) type ConnReadWriteFn = unsafe extern "C" fn(*mut c_void, c_int) -> u32;
pub(crate) type ConnPopMsgFn = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
pub(crate) type MsgNewCallFn = unsafe extern "C" fn(
    *const c_char,
    *const c_char,
    *const c_char,
    *const c_char,
) -> *mut c_void;
pub(crate) type MsgIsSignalFn =
    unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> u32;
pub(crate) type MsgGetPathFn = unsafe extern "C" fn(*mut c_void) -> *const c_char;
pub(crate) type MsgUnrefFn = unsafe extern "C" fn(*mut c_void);
pub(crate) type IterInitFn = unsafe extern "C" fn(*mut c_void, *mut DBusMessageIter) -> u32;
pub(crate) type IterInitAppendFn = unsafe extern "C" fn(*mut c_void, *mut DBusMessageIter);
pub(crate) type IterAppendBasicFn =
    unsafe extern "C" fn(*mut DBusMessageIter, c_int, *const c_void) -> u32;
pub(crate) type IterOpenContFn =
    unsafe extern "C" fn(*mut DBusMessageIter, c_int, *const c_char, *mut DBusMessageIter) -> u32;
pub(crate) type IterCloseContFn =
    unsafe extern "C" fn(*mut DBusMessageIter, *mut DBusMessageIter) -> u32;
pub(crate) type IterGetArgTypeFn = unsafe extern "C" fn(*mut DBusMessageIter) -> c_int;
pub(crate) type IterNextFn = unsafe extern "C" fn(*mut DBusMessageIter) -> u32;
pub(crate) type IterRecurseFn = unsafe extern "C" fn(*mut DBusMessageIter, *mut DBusMessageIter);
pub(crate) type IterGetBasicFn = unsafe extern "C" fn(*mut DBusMessageIter, *mut c_void);

pub(crate) struct LibDbus {
    lib: *mut c_void,
    pub(crate) err_init: ErrorInitFn,
    pub(crate) err_free: ErrorFreeFn,
    pub(crate) err_is_set: ErrorIsSetFn,
    pub(crate) bus_get: BusGetFn,
    pub(crate) bus_add_match: BusAddMatchFn,
    pub(crate) conn_flush: ConnFlushFn,
    pub(crate) conn_send_block: ConnSendBlockFn,
    pub(crate) conn_rw: ConnReadWriteFn,
    pub(crate) conn_pop: ConnPopMsgFn,
    pub(crate) msg_new_call: MsgNewCallFn,
    pub(crate) msg_is_sig: MsgIsSignalFn,
    pub(crate) msg_get_path: MsgGetPathFn,
    pub(crate) msg_unref: MsgUnrefFn,
    pub(crate) iter_init: IterInitFn,
    pub(crate) iter_init_append: IterInitAppendFn,
    pub(crate) iter_append_basic: IterAppendBasicFn,
    pub(crate) iter_open_cont: IterOpenContFn,
    pub(crate) iter_close_cont: IterCloseContFn,
    pub(crate) iter_type: IterGetArgTypeFn,
    pub(crate) iter_next: IterNextFn,
    pub(crate) iter_recurse: IterRecurseFn,
    pub(crate) iter_basic: IterGetBasicFn,
}

unsafe fn sym<T>(lib: *mut c_void, name: &CStr) -> Option<T> {
    let p = dlsym(lib, name.as_ptr());
    if p.is_null() {
        None
    } else {
        Some(std::mem::transmute_copy(&p))
    }
}

impl LibDbus {
    pub(crate) fn load() -> Option<Self> {
        unsafe {
            let lib = dlopen(c"libdbus-1.so.3".as_ptr(), RTLD_LAZY);
            if lib.is_null() {
                return None;
            }
            let me = Self {
                lib,
                err_init: sym(lib, c"dbus_error_init")?,
                err_free: sym(lib, c"dbus_error_free")?,
                err_is_set: sym(lib, c"dbus_error_is_set")?,
                bus_get: sym(lib, c"dbus_bus_get")?,
                bus_add_match: sym(lib, c"dbus_bus_add_match")?,
                conn_flush: sym(lib, c"dbus_connection_flush")?,
                conn_send_block: sym(lib, c"dbus_connection_send_with_reply_and_block")?,
                conn_rw: sym(lib, c"dbus_connection_read_write")?,
                conn_pop: sym(lib, c"dbus_connection_pop_message")?,
                msg_new_call: sym(lib, c"dbus_message_new_method_call")?,
                msg_is_sig: sym(lib, c"dbus_message_is_signal")?,
                msg_get_path: sym(lib, c"dbus_message_get_path")?,
                msg_unref: sym(lib, c"dbus_message_unref")?,
                iter_init: sym(lib, c"dbus_message_iter_init")?,
                iter_init_append: sym(lib, c"dbus_message_iter_init_append")?,
                iter_append_basic: sym(lib, c"dbus_message_iter_append_basic")?,
                iter_open_cont: sym(lib, c"dbus_message_iter_open_container")?,
                iter_close_cont: sym(lib, c"dbus_message_iter_close_container")?,
                iter_type: sym(lib, c"dbus_message_iter_get_arg_type")?,
                iter_next: sym(lib, c"dbus_message_iter_next")?,
                iter_recurse: sym(lib, c"dbus_message_iter_recurse")?,
                iter_basic: sym(lib, c"dbus_message_iter_get_basic")?,
            };
            Some(me)
        }
    }

    pub(crate) unsafe fn append_dict_str(&self, dict: &mut DBusMessageIter, key: &str, val: &str) {
        let ck = CString::new(key).unwrap();
        let cv = CString::new(val).unwrap();
        let mut entry = DBusMessageIter::default();
        let mut var = DBusMessageIter::default();
        (self.iter_open_cont)(dict, DBUS_TYPE_DICT_ENTRY, ptr::null(), &mut entry);
        let kp = ck.as_ptr();
        (self.iter_append_basic)(&mut entry, DBUS_TYPE_STRING, &kp as *const *const c_char as *const c_void);
        (self.iter_open_cont)(&mut entry, DBUS_TYPE_VARIANT, c"s".as_ptr(), &mut var);
        let vp = cv.as_ptr();
        (self.iter_append_basic)(&mut var, DBUS_TYPE_STRING, &vp as *const *const c_char as *const c_void);
        (self.iter_close_cont)(&mut entry, &mut var);
        (self.iter_close_cont)(dict, &mut entry);
    }

    pub(crate) unsafe fn append_dict_u32(&self, dict: &mut DBusMessageIter, key: &str, val: u32) {
        let ck = CString::new(key).unwrap();
        let mut entry = DBusMessageIter::default();
        let mut var = DBusMessageIter::default();
        (self.iter_open_cont)(dict, DBUS_TYPE_DICT_ENTRY, ptr::null(), &mut entry);
        let kp = ck.as_ptr();
        (self.iter_append_basic)(&mut entry, DBUS_TYPE_STRING, &kp as *const *const c_char as *const c_void);
        (self.iter_open_cont)(&mut entry, DBUS_TYPE_VARIANT, c"u".as_ptr(), &mut var);
        (self.iter_append_basic)(&mut var, DBUS_TYPE_UINT32, &val as *const u32 as *const c_void);
        (self.iter_close_cont)(&mut entry, &mut var);
        (self.iter_close_cont)(dict, &mut entry);
    }

    pub(crate) unsafe fn append_dict_bool(&self, dict: &mut DBusMessageIter, key: &str, val: bool) {
        let ck = CString::new(key).unwrap();
        let mut entry = DBusMessageIter::default();
        let mut var = DBusMessageIter::default();
        (self.iter_open_cont)(dict, DBUS_TYPE_DICT_ENTRY, ptr::null(), &mut entry);
        let kp = ck.as_ptr();
        (self.iter_append_basic)(&mut entry, DBUS_TYPE_STRING, &kp as *const *const c_char as *const c_void);
        (self.iter_open_cont)(&mut entry, DBUS_TYPE_VARIANT, c"b".as_ptr(), &mut var);
        let bval: u32 = u32::from(val);
        (self.iter_append_basic)(&mut var, DBUS_TYPE_BOOLEAN, &bval as *const u32 as *const c_void);
        (self.iter_close_cont)(&mut entry, &mut var);
        (self.iter_close_cont)(dict, &mut entry);
    }

    pub(crate) unsafe fn read_str(&self, it: &mut DBusMessageIter) -> Option<String> {
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

    pub(crate) unsafe fn wait_response(
        &self,
        conn: *mut c_void,
        req_path: &str,
        stopping: &AtomicBool,
    ) -> Option<(u32, *mut c_void)> {
        let t0 = Instant::now();
        let iface = c"org.freedesktop.portal.Request".as_ptr();
        let member = c"Response".as_ptr();
        while t0.elapsed() < PICKER_TIMEOUT {
            if stopping.load(Ordering::Relaxed) {
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
                if (self.msg_is_sig)(msg, iface, member) != 0 {
                    let p = (self.msg_get_path)(msg);
                    if !p.is_null() && CStr::from_ptr(p).to_string_lossy() == req_path {
                        let mut it = DBusMessageIter::default();
                        let mut code: u32 = 2;
                        if (self.iter_init)(msg, &mut it) != 0
                            && (self.iter_type)(&mut it) == DBUS_TYPE_UINT32
                        {
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

    pub(crate) unsafe fn dict_lookup_str(
        &self,
        msg: *mut c_void,
        target_key: &str,
    ) -> Option<String> {
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
                if k == target_key
                    && (self.iter_next)(&mut entry) != 0
                    && (self.iter_type)(&mut entry) == DBUS_TYPE_VARIANT
                {
                    let mut var = DBusMessageIter::default();
                    (self.iter_recurse)(&mut entry, &mut var);
                    return self.read_str(&mut var);
                }
            }
            (self.iter_next)(&mut arr);
        }
        None
    }

    pub(crate) unsafe fn parse_first_stream(&self, msg: *mut c_void) -> Option<(u32, i32, i32)> {
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
                if k == "streams"
                    && (self.iter_next)(&mut entry) != 0
                    && (self.iter_type)(&mut entry) == DBUS_TYPE_VARIANT
                {
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
                    if (self.iter_next)(&mut st) == 0
                        || (self.iter_type)(&mut st) != DBUS_TYPE_ARRAY
                    {
                        return None;
                    }
                    let mut props = DBusMessageIter::default();
                    (self.iter_recurse)(&mut st, &mut props);
                    let (mut w, mut h): (i32, i32) = (0, 0);
                    while (self.iter_type)(&mut props) == DBUS_TYPE_DICT_ENTRY {
                        let mut pe = DBusMessageIter::default();
                        (self.iter_recurse)(&mut props, &mut pe);
                        if let Some(pk) = self.read_str(&mut pe) {
                            if pk == "size"
                                && (self.iter_next)(&mut pe) != 0
                                && (self.iter_type)(&mut pe) == DBUS_TYPE_VARIANT
                            {
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

    pub(crate) unsafe fn close_session(&self, conn: *mut c_void, session: &str) {
        let Ok(c_sess) = CString::new(session) else {
            return;
        };
        let msg = (self.msg_new_call)(
            c"org.freedesktop.portal.Desktop".as_ptr(),
            c"/org/freedesktop/portal/desktop".as_ptr(),
            c"org.freedesktop.portal.ScreenCast".as_ptr(),
            c"CloseSession".as_ptr(),
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
