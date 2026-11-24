use std::ffi::{c_char, c_int, c_long, c_void, CString};
use std::ptr;

const RTLD_LAZY: c_int = 1;

// libcurl option constants (stable ABI across all libcurl 7/8 releases)
const CURLOPT_WRITEDATA: c_int = 10001;
const CURLOPT_URL: c_int = 10002;
const CURLOPT_READDATA: c_int = 10009;
const CURLOPT_TIMEOUT: c_int = 13;
const CURLOPT_POST: c_int = 47;
const CURLOPT_FOLLOWLOCATION: c_int = 52;
const CURLOPT_NOSIGNAL: c_int = 99;
const CURLOPT_POSTFIELDSIZE_LARGE: c_int = 30120;
const CURLOPT_WRITEFUNCTION: c_int = 20011;
const CURLOPT_READFUNCTION: c_int = 20012;
const CURLOPT_DOH_URL: c_int = 10282;

const CURLINFO_RESPONSE_CODE: c_int = 0x200000 + 2;

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

type CurlGlobalInitFn = unsafe extern "C" fn(c_long) -> c_int;
type CurlEasyInitFn = unsafe extern "C" fn() -> *mut c_void;
type CurlEasyCleanupFn = unsafe extern "C" fn(*mut c_void);
type CurlEasyResetFn = unsafe extern "C" fn(*mut c_void);
type CurlEasyPerformFn = unsafe extern "C" fn(*mut c_void) -> c_int;
type CurlEasySetoptPtrFn = unsafe extern "C" fn(*mut c_void, c_int, *const c_void) -> c_int;
type CurlEasySetoptLongFn = unsafe extern "C" fn(*mut c_void, c_int, c_long) -> c_int;
type CurlEasySetoptI64Fn = unsafe extern "C" fn(*mut c_void, c_int, i64) -> c_int;
type CurlEasyGetinfoLongFn = unsafe extern "C" fn(*mut c_void, c_int, *mut c_long) -> c_int;

type WriteCallback = unsafe extern "C" fn(*const c_char, usize, usize, *mut c_void) -> usize;
type ReadCallback = unsafe extern "C" fn(*mut c_char, usize, usize, *mut c_void) -> usize;

pub(crate) struct LibCurl {
    lib: *mut c_void,
    handle: *mut c_void,
    easy_cleanup: CurlEasyCleanupFn,
    easy_reset: CurlEasyResetFn,
    easy_perform: CurlEasyPerformFn,
    setopt_ptr: CurlEasySetoptPtrFn,
    setopt_long: CurlEasySetoptLongFn,
    setopt_i64: CurlEasySetoptI64Fn,
    getinfo_long: CurlEasyGetinfoLongFn,
}

impl LibCurl {
    pub(crate) fn load() -> Option<Self> {
        unsafe {
            let lib = dlopen(c"libcurl.so.4".as_ptr(), RTLD_LAZY);
            if lib.is_null() {
                return None;
            }
            let global_init_p = dlsym(lib, c"curl_global_init".as_ptr());
            let easy_init_p = dlsym(lib, c"curl_easy_init".as_ptr());
            let easy_cleanup_p = dlsym(lib, c"curl_easy_cleanup".as_ptr());
            let easy_reset_p = dlsym(lib, c"curl_easy_reset".as_ptr());
            let easy_perform_p = dlsym(lib, c"curl_easy_perform".as_ptr());
            let setopt_p = dlsym(lib, c"curl_easy_setopt".as_ptr());
            let getinfo_p = dlsym(lib, c"curl_easy_getinfo".as_ptr());
            if global_init_p.is_null()
                || easy_init_p.is_null()
                || easy_cleanup_p.is_null()
                || easy_reset_p.is_null()
                || easy_perform_p.is_null()
                || setopt_p.is_null()
                || getinfo_p.is_null()
            {
                dlclose(lib);
                return None;
            }
            let global_init: CurlGlobalInitFn =
                std::mem::transmute::<*mut c_void, CurlGlobalInitFn>(global_init_p);
            let easy_init: CurlEasyInitFn =
                std::mem::transmute::<*mut c_void, CurlEasyInitFn>(easy_init_p);
            let _ = global_init(3); // CURL_GLOBAL_DEFAULT
            let handle = easy_init();
            if handle.is_null() {
                dlclose(lib);
                return None;
            }
            Some(Self {
                lib,
                handle,
                easy_cleanup: std::mem::transmute::<*mut c_void, CurlEasyCleanupFn>(easy_cleanup_p),
                easy_reset: std::mem::transmute::<*mut c_void, CurlEasyResetFn>(easy_reset_p),
                easy_perform: std::mem::transmute::<*mut c_void, CurlEasyPerformFn>(easy_perform_p),
                setopt_ptr: std::mem::transmute::<*mut c_void, CurlEasySetoptPtrFn>(setopt_p),
                setopt_long: std::mem::transmute::<*mut c_void, CurlEasySetoptLongFn>(setopt_p),
                setopt_i64: std::mem::transmute::<*mut c_void, CurlEasySetoptI64Fn>(setopt_p),
                getinfo_long: std::mem::transmute::<*mut c_void, CurlEasyGetinfoLongFn>(getinfo_p),
            })
        }
    }

    pub(crate) fn get_bytes(
        &self,
        url: &str,
        timeout_secs: c_long,
        doh_url: Option<&str>,
    ) -> Result<(c_long, Vec<u8>), c_int> {
        let c_url = CString::new(url).map_err(|_| -1)?;
        let c_doh = match doh_url {
            Some(d) => Some(CString::new(d).map_err(|_| -1)?),
            None => None,
        };
        let mut body: Vec<u8> = Vec::new();
        unsafe {
            let h = self.handle;
            (self.easy_reset)(h);
            (self.setopt_ptr)(h, CURLOPT_URL, c_url.as_ptr() as *const c_void);
            (self.setopt_long)(h, CURLOPT_TIMEOUT, timeout_secs);
            (self.setopt_long)(h, CURLOPT_FOLLOWLOCATION, 1);
            (self.setopt_long)(h, CURLOPT_NOSIGNAL, 1);
            if let Some(ref d) = c_doh {
                (self.setopt_ptr)(h, CURLOPT_DOH_URL, d.as_ptr() as *const c_void);
            }
            let cb: WriteCallback = write_vec_cb;
            (self.setopt_ptr)(h, CURLOPT_WRITEFUNCTION, cb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_WRITEDATA, &mut body as *mut Vec<u8> as *const c_void);

            let rc = (self.easy_perform)(h);
            let mut status: c_long = 0;
            if rc == 0 {
                (self.getinfo_long)(h, CURLINFO_RESPONSE_CODE, &mut status);
            }
            if rc != 0 {
                Err(rc)
            } else {
                Ok((status, body))
            }
        }
    }

    pub(crate) fn get_discard(&self, url: &str, timeout_secs: c_long) -> Result<(c_long, u64), c_int> {
        let c_url = CString::new(url).map_err(|_| -1)?;
        let mut count: u64 = 0;
        unsafe {
            let h = self.handle;
            (self.easy_reset)(h);
            (self.setopt_ptr)(h, CURLOPT_URL, c_url.as_ptr() as *const c_void);
            (self.setopt_long)(h, CURLOPT_TIMEOUT, timeout_secs);
            (self.setopt_long)(h, CURLOPT_FOLLOWLOCATION, 1);
            (self.setopt_long)(h, CURLOPT_NOSIGNAL, 1);
            let cb: WriteCallback = write_count_cb;
            (self.setopt_ptr)(h, CURLOPT_WRITEFUNCTION, cb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_WRITEDATA, &mut count as *mut u64 as *const c_void);

            let rc = (self.easy_perform)(h);
            let mut status: c_long = 0;
            if rc == 0 {
                (self.getinfo_long)(h, CURLINFO_RESPONSE_CODE, &mut status);
            }
            if rc != 0 {
                Err(rc)
            } else {
                Ok((status, count))
            }
        }
    }

    pub(crate) fn post_filler(
        &self,
        url: &str,
        total_bytes: u64,
        timeout_secs: c_long,
    ) -> Result<(c_long, u64), c_int> {
        let c_url = CString::new(url).map_err(|_| -1)?;
        let mut state = UploadState {
            remaining: total_bytes,
            sent: 0,
        };
        let mut discard: u64 = 0;
        unsafe {
            let h = self.handle;
            (self.easy_reset)(h);
            (self.setopt_ptr)(h, CURLOPT_URL, c_url.as_ptr() as *const c_void);
            (self.setopt_long)(h, CURLOPT_TIMEOUT, timeout_secs);
            (self.setopt_long)(h, CURLOPT_POST, 1);
            (self.setopt_long)(h, CURLOPT_NOSIGNAL, 1);
            (self.setopt_i64)(h, CURLOPT_POSTFIELDSIZE_LARGE, total_bytes as i64);

            let rcb: ReadCallback = read_filler_cb;
            (self.setopt_ptr)(h, CURLOPT_READFUNCTION, rcb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_READDATA, &mut state as *mut UploadState as *const c_void);

            let wcb: WriteCallback = write_count_cb;
            (self.setopt_ptr)(h, CURLOPT_WRITEFUNCTION, wcb as *const c_void);
            (self.setopt_ptr)(h, CURLOPT_WRITEDATA, &mut discard as *mut u64 as *const c_void);

            let rc = (self.easy_perform)(h);
            let mut status: c_long = 0;
            if rc == 0 {
                (self.getinfo_long)(h, CURLINFO_RESPONSE_CODE, &mut status);
            }
            if rc != 0 {
                Err(rc)
            } else {
                Ok((status, state.sent))
            }
        }
    }
}

impl Drop for LibCurl {
    fn drop(&mut self) {
        unsafe {
            (self.easy_cleanup)(self.handle);
            dlclose(self.lib);
        }
    }
}

struct UploadState {
    remaining: u64,
    sent: u64,
}

unsafe extern "C" fn write_vec_cb(
    ptr: *const c_char,
    size: usize,
    nmemb: usize,
    userdata: *mut c_void,
) -> usize {
    let n = size.saturating_mul(nmemb);
    if userdata.is_null() || ptr.is_null() {
        return 0;
    }
    let vec = &mut *(userdata as *mut Vec<u8>);
    let slice = std::slice::from_raw_parts(ptr as *const u8, n);
    vec.extend_from_slice(slice);
    n
}

unsafe extern "C" fn write_count_cb(
    _ptr: *const c_char,
    size: usize,
    nmemb: usize,
    userdata: *mut c_void,
) -> usize {
    let n = size.saturating_mul(nmemb);
    if !userdata.is_null() {
        let count = &mut *(userdata as *mut u64);
        *count = count.saturating_add(n as u64);
    }
    n
}

unsafe extern "C" fn read_filler_cb(
    dst: *mut c_char,
    size: usize,
    nmemb: usize,
    userdata: *mut c_void,
) -> usize {
    if userdata.is_null() || dst.is_null() {
        return 0;
    }
    let state = &mut *(userdata as *mut UploadState);
    if state.remaining == 0 {
        return 0;
    }
    let cap = size.saturating_mul(nmemb) as u64;
    let to_write = cap.min(state.remaining) as usize;
    ptr::write_bytes(dst as *mut u8, b'x', to_write);
    state.remaining -= to_write as u64;
    state.sent += to_write as u64;
    to_write
}
