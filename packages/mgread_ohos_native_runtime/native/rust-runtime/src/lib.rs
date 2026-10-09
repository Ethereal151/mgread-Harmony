//! Minimal OHOS Native/Rust Runtime ABI.
//!
//! The OHOS application does not ship a built-in Rust data source. This
//! library remains a source-neutral lifecycle bridge for ABI compatibility;
//! source implementations belong to explicitly imported platform artifacts.

use std::collections::HashSet;
use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::sync::{LazyLock, Mutex};
use std::thread::JoinHandle;

use mgread_native_runtime::serve_embedded;
use serde_json::Value;

const MGREAD_RUNTIME_UNSUPPORTED: i32 = 9;
const MGREAD_RUNTIME_CRASHED: i32 = 8;

static LAST_ERROR: LazyLock<Mutex<String>> = LazyLock::new(|| Mutex::new(String::new()));
static VERSION: &[u8] = b"mgread-ohos-native-runtime/0.1.0 abi=1\0";

fn set_last_error(value: impl Into<String>) {
    if let Ok(mut error) = LAST_ERROR.lock() {
        *error = value.into();
    }
}

struct State {
    started: bool,
    generation: u64,
    cancelled: HashSet<String>,
}

pub struct Runtime {
    state: Mutex<State>,
    config: String,
}

#[repr(C)]
pub struct mgread_runtime_handle {
    runtime: Runtime,
}

fn input<'a>(value: *const c_char) -> Option<&'a str> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value).to_str().ok() }
}

fn output(value: &str, target: *mut *mut c_char) -> i32 {
    if target.is_null() {
        return 1;
    }
    let Ok(encoded) = CString::new(value.replace('\0', "")) else {
        return 1;
    };
    unsafe { *target = encoded.into_raw() };
    0
}

struct NativeHost {
    stop: Option<tokio::sync::oneshot::Sender<()>>,
    thread: Option<JoinHandle<Result<(), String>>>,
}

impl NativeHost {
    fn new() -> Self {
        Self { stop: None, thread: None }
    }

    fn stop(&mut self) -> i32 {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        if let Some(thread) = self.thread.take() {
            if thread.join().is_err() {
                set_last_error("OHOS native Rust worker thread panicked.");
                return MGREAD_RUNTIME_CRASHED;
            }
        }
        0
    }

    fn start(
        &mut self,
        root: &str,
        token: &str,
        native_library_dir: &str,
        test_mode: bool,
    ) -> Result<String, String> {
        let _ = self.stop();
        let (ready_tx, ready_rx) = std::sync::mpsc::sync_channel(1);
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
        let root = root.to_owned();
        let token = token.to_owned();
        let native_library_dir = native_library_dir.to_owned();
        let thread = std::thread::Builder::new()
            .name("mgread-native-ohos".to_owned())
            .spawn(move || {
                let runtime = tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(4)
                    .enable_all()
                    .build()
                    .map_err(|error| error.to_string())?;
                runtime.block_on(serve_embedded(
                    std::path::PathBuf::from(root),
                    token,
                    std::path::PathBuf::from(native_library_dir),
                    test_mode,
                    stop_rx,
                    |ready| {
                        let _ = ready_tx.send(serde_json::to_string(&ready).unwrap_or_default());
                    },
                ))
                .map_err(|error| error.to_string())
            })
            .map_err(|error| error.to_string())?;
        let ready = match ready_rx.recv_timeout(std::time::Duration::from_secs(25)) {
            Ok(ready) => ready,
            Err(_) => {
                let _ = stop_tx.send(());
                let _ = thread.join();
                return Err("OHOS native Rust worker did not become ready.".to_owned());
            }
        };
        if ready.is_empty() {
            let _ = stop_tx.send(());
            let _ = thread.join();
            return Err("OHOS native Rust worker returned an empty ready record.".to_owned());
        }
        self.stop = Some(stop_tx);
        self.thread = Some(thread);
        Ok(ready)
    }
}

#[repr(C)]
pub struct mgread_native_host_handle {
    host: Mutex<NativeHost>,
}

fn request_method(request: &str) -> Option<String> {
    serde_json::from_str::<Value>(request)
        .ok()?
        .get("method")?
        .as_str()
        .map(str::to_owned)
}

fn request_id(request: &str) -> Option<String> {
    serde_json::from_str::<Value>(request)
        .ok()?
        .get("requestId")?
        .as_str()
        .map(str::to_owned)
}

fn is_source_method(method: &str) -> bool {
    matches!(
        method,
        "discover"
            | "search"
            | "searchSuggestions"
            | "getDetail"
            | "getChapters"
            | "getContent"
            | "resource.get"
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn mgread_runtime_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn mgread_runtime_create(config_json: *const c_char) -> *mut mgread_runtime_handle {
    let Some(config) = input(config_json) else {
        return ptr::null_mut();
    };
    Box::into_raw(Box::new(mgread_runtime_handle {
        runtime: Runtime {
            state: Mutex::new(State {
                started: false,
                generation: 0,
                cancelled: HashSet::new(),
            }),
            config: config.to_owned(),
        },
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_start(runtime: *mut mgread_runtime_handle) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else {
        return 1;
    };
    let Ok(mut state) = runtime.runtime.state.lock() else {
        return 8;
    };
    state.started = true;
    state.generation = state.generation.saturating_add(1);
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_invoke(
    runtime: *mut mgread_runtime_handle,
    request_json: *const c_char,
    response_json: *mut *mut c_char,
) -> i32 {
    if response_json.is_null() {
        return 1;
    }
    unsafe { *response_json = ptr::null_mut() };
    let Some(runtime) = (unsafe { runtime.as_ref() }) else {
        return 1;
    };
    let Some(request) = input(request_json) else {
        return 1;
    };
    let method = request_method(request).unwrap_or_else(|| "runtime.fixed.invoke".to_owned());
    let request_id = request_id(request).unwrap_or_default();
    let (generation, started, cancelled) = match runtime.runtime.state.lock() {
        Ok(mut state) => {
            let cancelled = !request_id.is_empty() && state.cancelled.remove(&request_id);
            (state.generation, state.started, cancelled)
        }
        Err(_) => return 8,
    };
    if !started {
        return 2;
    }
    if cancelled {
        return 4;
    }
    if is_source_method(&method) {
        set_last_error("OHOS Rust Runtime has no built-in data source.");
        return MGREAD_RUNTIME_UNSUPPORTED;
    }
    let config_present = !runtime.runtime.config.is_empty();
    let response = format!(
        "{{\"ok\":true,\"abiVersion\":1,\"generation\":{},\"method\":\"{}\",\"configPresent\":{}}}",
        generation,
        method.replace('"', ""),
        config_present
    );
    output(&response, response_json)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_last_error(response_json: *mut *mut c_char) -> i32 {
    let Some(response_json) = (unsafe { response_json.as_mut() }) else {
        return 1;
    };
    let error = LAST_ERROR.lock().map(|value| value.clone()).unwrap_or_default();
    output(&error, response_json)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_cancel(
    runtime: *mut mgread_runtime_handle,
    request_id: *const c_char,
) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else {
        return 1;
    };
    let Some(request_id) = input(request_id) else {
        return 1;
    };
    if request_id.is_empty() {
        return 1;
    }
    let Ok(mut state) = runtime.runtime.state.lock() else {
        return 8;
    };
    if !state.started {
        return 2;
    }
    state.cancelled.insert(request_id.to_owned());
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_stop(runtime: *mut mgread_runtime_handle) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else {
        return 1;
    };
    let Ok(mut state) = runtime.runtime.state.lock() else {
        return 8;
    };
    state.started = false;
    state.cancelled.clear();
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_restart(runtime: *mut mgread_runtime_handle) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else {
        return 1;
    };
    let Ok(mut state) = runtime.runtime.state.lock() else {
        return 8;
    };
    state.started = true;
    state.cancelled.clear();
    state.generation = state.generation.saturating_add(1);
    0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_free_string(value: *mut c_char) {
    if !value.is_null() {
        unsafe { drop(CString::from_raw(value)) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_free(runtime: *mut mgread_runtime_handle) {
    if !runtime.is_null() {
        unsafe { drop(Box::from_raw(runtime)) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mgread_native_host_create() -> *mut mgread_native_host_handle {
    Box::into_raw(Box::new(mgread_native_host_handle {
        host: Mutex::new(NativeHost::new()),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_native_host_start(
    host: *mut mgread_native_host_handle,
    root: *const c_char,
    token: *const c_char,
    native_library_dir: *const c_char,
    test_mode: i32,
    ready_json: *mut *mut c_char,
) -> i32 {
    if ready_json.is_null() {
        return 1;
    }
    unsafe { *ready_json = ptr::null_mut() };
    let Some(host) = (unsafe { host.as_ref() }) else {
        return 1;
    };
    let Some(root) = input(root) else {
        return 1;
    };
    let Some(token) = input(token) else {
        return 1;
    };
    let Some(native_library_dir) = input(native_library_dir) else {
        return 1;
    };
    let Ok(mut host) = host.host.lock() else {
        return 8;
    };
    match host.start(root, token, native_library_dir, test_mode != 0) {
        Ok(ready) => output(&ready, ready_json),
        Err(error) => {
            set_last_error(error);
            5
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_native_host_stop(
    host: *mut mgread_native_host_handle,
) -> i32 {
    let Some(host) = (unsafe { host.as_ref() }) else {
        return 1;
    };
    let Ok(mut host) = host.host.lock() else {
        return 8;
    };
    host.stop()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_native_host_free(
    host: *mut mgread_native_host_handle,
) {
    if !host.is_null() {
        let host = unsafe { Box::from_raw(host) };
        if let Ok(mut host) = host.host.lock() {
            let _ = host.stop();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lifecycle_invoke_cancel_and_restart_are_bounded() {
        let config = CString::new(r#"{"dataRoot":"private"}"#).unwrap();
        let request = CString::new(r#"{"requestId":"one","method":"fixed"}"#).unwrap();
        let id = CString::new("one").unwrap();
        let runtime = mgread_runtime_create(config.as_ptr());
        assert!(!runtime.is_null());
        let mut response = ptr::null_mut();
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, 2);
        assert_eq!(unsafe { mgread_runtime_start(runtime) }, 0);
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, 0);
        assert!(unsafe { CStr::from_ptr(response) }.to_str().unwrap().contains("\"ok\":true"));
        unsafe { mgread_runtime_free_string(response) };
        assert_eq!(unsafe { mgread_runtime_cancel(runtime, id.as_ptr()) }, 0);
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, 4);
        assert_eq!(unsafe { mgread_runtime_restart(runtime) }, 0);
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, 0);
        unsafe {
            mgread_runtime_free_string(response);
            mgread_runtime_free(runtime);
        }
    }

    #[test]
    fn source_methods_are_not_implemented_by_the_generic_bridge() {
        let config = CString::new("{}").unwrap();
        let request = CString::new(r#"{"requestId":"source","method":"discover"}"#).unwrap();
        let runtime = mgread_runtime_create(config.as_ptr());
        assert_eq!(unsafe { mgread_runtime_start(runtime) }, 0);
        let mut response = ptr::null_mut();
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, MGREAD_RUNTIME_UNSUPPORTED);
        unsafe { mgread_runtime_free(runtime) };
    }
}
