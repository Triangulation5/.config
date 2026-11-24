use crate::portal_dbus::{
    DBusError, DBusMessageIter, LibDbus, DBUS_BUS_SESSION, DBUS_TYPE_ARRAY, DBUS_TYPE_OBJECT_PATH,
    DBUS_TYPE_STRING, DBUS_TYPE_UNIX_FD,
};
use std::env;
use std::ffi::{c_char, c_int, c_void, CString};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;

const F_SETFD: c_int = 2;

extern "C" {
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
}

pub(crate) struct PortalSession {
    pub(crate) conn: *mut c_void,
    pub(crate) session: String,
    pub(crate) stream_id: u32,
    pub(crate) width: i32,
    pub(crate) height: i32,
    pub(crate) conn_fd: Option<c_int>,
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

/// Performs the 4-step xdg-desktop-portal ScreenCast D-Bus handshake:
/// `CreateSession` -> `SelectSources` -> `Start` -> `OpenPipeWireRemote`.
pub(crate) unsafe fn open_screencast_session(
    dbus: &LibDbus,
    pid: u32,
    cursor_yes: bool,
    persist: u32,
    stopping: &AtomicBool,
) -> PortalSession {
    let mut tok_n = 0u32;
    let mut next_tok = || {
        tok_n += 1;
        format!("quickshell_{}_{}", pid, tok_n)
    };

    let mut err = DBusError::default();
    (dbus.err_init)(&mut err);
    let conn = (dbus.bus_get)(DBUS_BUS_SESSION, &mut err);
    if conn.is_null() || (dbus.err_is_set)(&err) != 0 {
        (dbus.err_free)(&mut err);
        eprintln!("Screen share portal error: cannot connect to session D-Bus");
        std::process::exit(1);
    }

    let rule = c"type='signal',interface='org.freedesktop.portal.Request',member='Response'".as_ptr();
    (dbus.bus_add_match)(conn, rule, &mut err);
    if (dbus.err_is_set)(&err) != 0 {
        (dbus.err_free)(&mut err);
        eprintln!("Screen share portal error: cannot subscribe to Request.Response");
        std::process::exit(1);
    }
    (dbus.conn_flush)(conn);

    let dest = c"org.freedesktop.portal.Desktop".as_ptr();
    let path = c"/org/freedesktop/portal/desktop".as_ptr();
    let sc_iface = c"org.freedesktop.portal.ScreenCast".as_ptr();
    let pw_iface = c"org.freedesktop.portal.PipeWire".as_ptr();

    // 1. CreateSession
    let call1 = (dbus.msg_new_call)(dest, path, sc_iface, c"CreateSession".as_ptr());
    let mut it1 = DBusMessageIter::default();
    let mut d1 = DBusMessageIter::default();
    (dbus.iter_init_append)(call1, &mut it1);
    (dbus.iter_open_cont)(&mut it1, DBUS_TYPE_ARRAY, c"{sv}".as_ptr(), &mut d1);
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

    let (code1, sig1) = match dbus.wait_response(conn, &req1, stopping) {
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

    let call2 = (dbus.msg_new_call)(dest, path, sc_iface, c"SelectSources".as_ptr());
    let mut it2 = DBusMessageIter::default();
    let mut d2 = DBusMessageIter::default();
    (dbus.iter_init_append)(call2, &mut it2);
    let sp = c_sess.as_ptr();
    (dbus.iter_append_basic)(&mut it2, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
    (dbus.iter_open_cont)(&mut it2, DBUS_TYPE_ARRAY, c"{sv}".as_ptr(), &mut d2);
    dbus.append_dict_str(&mut d2, "handle_token", &next_tok());
    dbus.append_dict_u32(&mut d2, "types", 1); // MONITOR
    dbus.append_dict_bool(&mut d2, "multiple", false);
    dbus.append_dict_u32(&mut d2, "cursor_mode", if cursor_yes { 1 } else { 2 });
    dbus.append_dict_u32(&mut d2, "persist_mode", persist);
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

    let (code2, sig2) = match dbus.wait_response(conn, &req2, stopping) {
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
    let call3 = (dbus.msg_new_call)(dest, path, sc_iface, c"Start".as_ptr());
    let mut it3 = DBusMessageIter::default();
    let mut d3 = DBusMessageIter::default();
    (dbus.iter_init_append)(call3, &mut it3);
    (dbus.iter_append_basic)(&mut it3, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
    let empty = c"".as_ptr();
    (dbus.iter_append_basic)(&mut it3, DBUS_TYPE_STRING, &empty as *const *const c_char as *const c_void);
    (dbus.iter_open_cont)(&mut it3, DBUS_TYPE_ARRAY, c"{sv}".as_ptr(), &mut d3);
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

    let (code3, sig3) = match dbus.wait_response(conn, &req3, stopping) {
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
    let call4 = (dbus.msg_new_call)(dest, path, pw_iface, c"OpenPipeWireRemote".as_ptr());
    let mut it4 = DBusMessageIter::default();
    let mut d4 = DBusMessageIter::default();
    (dbus.iter_init_append)(call4, &mut it4);
    (dbus.iter_append_basic)(&mut it4, DBUS_TYPE_OBJECT_PATH, &sp as *const *const c_char as *const c_void);
    (dbus.iter_open_cont)(&mut it4, DBUS_TYPE_ARRAY, c"{sv}".as_ptr(), &mut d4);
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

    PortalSession {
        conn,
        session,
        stream_id,
        width,
        height,
        conn_fd,
    }
}
