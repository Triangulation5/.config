use std::ffi::{c_char, c_int, c_void};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[repr(C)]
#[derive(Default)]
struct NvmlUtilization {
    gpu: u32,
    memory: u32,
}

#[repr(C)]
#[derive(Default)]
struct NvmlMemory {
    total: u64,
    free: u64,
    used: u64,
}

const RTLD_LAZY: c_int = 1;
const NVML_TEMPERATURE_GPU: u32 = 0;

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

type NvmlInitFn = unsafe extern "C" fn() -> c_int;
type NvmlShutdownFn = unsafe extern "C" fn() -> c_int;
type NvmlGetHandleFn = unsafe extern "C" fn(u32, *mut *mut c_void) -> c_int;
type NvmlGetUtilFn = unsafe extern "C" fn(*mut c_void, *mut NvmlUtilization) -> c_int;
type NvmlGetTempFn = unsafe extern "C" fn(*mut c_void, u32, *mut u32) -> c_int;
type NvmlGetMemFn = unsafe extern "C" fn(*mut c_void, *mut NvmlMemory) -> c_int;

pub(crate) struct NvmlClient {
    lib: *mut c_void,
    device: *mut c_void,
    shutdown: NvmlShutdownFn,
    get_util: NvmlGetUtilFn,
    get_temp: NvmlGetTempFn,
    get_mem: NvmlGetMemFn,
}

impl NvmlClient {
    pub(crate) fn open() -> Option<Self> {
        unsafe {
            let lib = dlopen(c"libnvidia-ml.so.1".as_ptr(), RTLD_LAZY);
            if lib.is_null() {
                return None;
            }
            let init_sym = dlsym(lib, c"nvmlInit_v2".as_ptr());
            let shutdown_sym = dlsym(lib, c"nvmlShutdown".as_ptr());
            let handle_sym = dlsym(lib, c"nvmlDeviceGetHandleByIndex_v2".as_ptr());
            let util_sym = dlsym(lib, c"nvmlDeviceGetUtilizationRates".as_ptr());
            let temp_sym = dlsym(lib, c"nvmlDeviceGetTemperature".as_ptr());
            let mem_sym = dlsym(lib, c"nvmlDeviceGetMemoryInfo".as_ptr());

            if init_sym.is_null()
                || shutdown_sym.is_null()
                || handle_sym.is_null()
                || util_sym.is_null()
                || temp_sym.is_null()
                || mem_sym.is_null()
            {
                dlclose(lib);
                return None;
            }

            let init: NvmlInitFn = std::mem::transmute::<*mut c_void, NvmlInitFn>(init_sym);
            let shutdown: NvmlShutdownFn =
                std::mem::transmute::<*mut c_void, NvmlShutdownFn>(shutdown_sym);
            let get_handle: NvmlGetHandleFn =
                std::mem::transmute::<*mut c_void, NvmlGetHandleFn>(handle_sym);
            let get_util: NvmlGetUtilFn =
                std::mem::transmute::<*mut c_void, NvmlGetUtilFn>(util_sym);
            let get_temp: NvmlGetTempFn =
                std::mem::transmute::<*mut c_void, NvmlGetTempFn>(temp_sym);
            let get_mem: NvmlGetMemFn =
                std::mem::transmute::<*mut c_void, NvmlGetMemFn>(mem_sym);

            if init() != 0 {
                dlclose(lib);
                return None;
            }

            let mut device: *mut c_void = std::ptr::null_mut();
            if get_handle(0, &mut device) != 0 || device.is_null() {
                shutdown();
                dlclose(lib);
                return None;
            }

            Some(Self {
                lib,
                device,
                shutdown,
                get_util,
                get_temp,
                get_mem,
            })
        }
    }

    pub(crate) fn sample(&self) -> Option<(u32, u32, u64, u64)> {
        let mut util = NvmlUtilization::default();
        let mut temp: u32 = 0;
        let mut mem = NvmlMemory::default();
        unsafe {
            let u_ok = (self.get_util)(self.device, &mut util) == 0;
            let t_ok = (self.get_temp)(self.device, NVML_TEMPERATURE_GPU, &mut temp) == 0;
            let m_ok = (self.get_mem)(self.device, &mut mem) == 0;
            if !u_ok && !t_ok && !m_ok {
                return None;
            }
        }
        let used_mib = mem.used / (1024 * 1024);
        let total_mib = mem.total / (1024 * 1024);
        Some((util.gpu, temp, used_mib, total_mib))
    }
}

impl Drop for NvmlClient {
    fn drop(&mut self) {
        unsafe {
            (self.shutdown)();
            dlclose(self.lib);
        }
    }
}

pub(crate) struct GpuInfo {
    pub(crate) vendor: &'static str,
    pub(crate) device_path: Option<PathBuf>,
    pub(crate) amd_temp_path: Option<PathBuf>,
    pub(crate) has_vram: bool,
    pub(crate) nvml: Option<NvmlClient>,
}

fn detect_amd_hwmon_temp(dev: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(dev.join("hwmon")).ok()?;
    for h in entries.flatten() {
        let candidate = h.path().join("temp1_input");
        if candidate.exists() {
            return Some(candidate);
        }
    }
    None
}

pub(crate) fn detect_gpu() -> GpuInfo {
    if let Some(nvml) = NvmlClient::open() {
        return GpuInfo {
            vendor: "nvidia",
            device_path: None,
            amd_temp_path: None,
            has_vram: true,
            nvml: Some(nvml),
        };
    }

    let nv_check = Command::new("nvidia-smi")
        .arg("-L")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();

    if let Ok(status) = nv_check {
        if status.success() {
            return GpuInfo {
                vendor: "nvidia",
                device_path: None,
                amd_temp_path: None,
                has_vram: true,
                nvml: None,
            };
        }
    }

    let drm_dir = Path::new("/sys/class/drm");
    if let Ok(entries) = fs::read_dir(drm_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with("card") && !name_str.contains('-') {
                let dev_path = entry.path().join("device");
                let vendor_file = dev_path.join("vendor");
                if let Ok(vendor) = fs::read_to_string(&vendor_file) {
                    if vendor.trim() == "0x1002" && dev_path.join("gpu_busy_percent").exists() {
                        let has_vram = dev_path.join("mem_info_vram_total").exists();
                        let amd_temp_path = detect_amd_hwmon_temp(&dev_path);
                        return GpuInfo {
                            vendor: "amd",
                            device_path: Some(dev_path),
                            amd_temp_path,
                            has_vram,
                            nvml: None,
                        };
                    }
                }
            }
        }
    }

    GpuInfo {
        vendor: "none",
        device_path: None,
        amd_temp_path: None,
        has_vram: false,
        nvml: None,
    }
}

pub(crate) fn sample_amd_gpu(dev: &Path, temp_path: Option<&Path>) -> (u32, i32, u64, u64) {
    let busy = fs::read_to_string(dev.join("gpu_busy_percent"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    let temp = temp_path
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|t| t.trim().parse().ok())
        .unwrap_or(0);

    let vu = fs::read_to_string(dev.join("mem_info_vram_used"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    let vt = fs::read_to_string(dev.join("mem_info_vram_total"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    (busy, temp, vu, vt)
}
