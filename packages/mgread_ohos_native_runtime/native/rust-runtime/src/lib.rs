//! Minimal OHOS Native/Rust Runtime ABI.
//!
//! The public boundary intentionally has no Rust types or allocator ownership.
//! The C++ shim runs these calls away from the ArkTS/UI thread and owns the
//! returned string through `mgread_runtime_free_string`.

use std::collections::HashSet;
use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::sync::Mutex;

static VERSION: &[u8] = b"mgread-ohos-native-runtime/0.1.0 abi=1\0";

struct State { started: bool, generation: u64, cancelled: HashSet<String> }

pub struct Runtime { state: Mutex<State>, config: String }

#[repr(C)]
pub struct mgread_runtime_handle { runtime: Runtime }

fn input<'a>(value: *const c_char) -> Option<&'a str> {
    if value.is_null() { return None; }
    unsafe { CStr::from_ptr(value).to_str().ok() }
}

fn output(value: &str, target: *mut *mut c_char) -> i32 {
    if target.is_null() { return 1; }
    let Ok(encoded) = CString::new(value.replace('\0', "")) else { return 1; };
    unsafe { *target = encoded.into_raw(); }
    0
}

fn json_string(json: &str, key: &str) -> Option<String> {
    let marker = format!("\"{key}\":\"");
    let start = json.find(&marker)? + marker.len();
    let rest = &json[start..];
    Some(rest[..rest.find('"')?].to_owned())
}

#[unsafe(no_mangle)]
pub extern "C" fn mgread_runtime_version() -> *const c_char { VERSION.as_ptr().cast() }

#[unsafe(no_mangle)]
pub extern "C" fn mgread_runtime_create(config_json: *const c_char) -> *mut mgread_runtime_handle {
    let Some(config) = input(config_json) else { return ptr::null_mut(); };
    Box::into_raw(Box::new(mgread_runtime_handle { runtime: Runtime {
        state: Mutex::new(State { started: false, generation: 0, cancelled: HashSet::new() }),
        config: config.to_owned(),
    }}))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_start(runtime: *mut mgread_runtime_handle) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else { return 1; };
    let Ok(mut state) = runtime.runtime.state.lock() else { return 8; };
    state.started = true; state.generation = state.generation.saturating_add(1); 0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_invoke(runtime: *mut mgread_runtime_handle, request_json: *const c_char, response_json: *mut *mut c_char) -> i32 {
    if response_json.is_null() { return 1; }
    unsafe { *response_json = ptr::null_mut(); }
    let Some(runtime) = (unsafe { runtime.as_ref() }) else { return 1; };
    let Some(request) = (unsafe { input(request_json) }) else { return 1; };
    let request_id = json_string(request, "requestId").unwrap_or_default();
    let method = json_string(request, "method").unwrap_or_else(|| "runtime.fixed.invoke".to_owned());
    let Ok(mut state) = runtime.runtime.state.lock() else { return 8; };
    if !state.started { return 2; }
    if !request_id.is_empty() && state.cancelled.remove(&request_id) { return 4; }
    let response = format!("{{\"ok\":true,\"abiVersion\":1,\"generation\":{},\"method\":\"{}\",\"configPresent\":{}}}", state.generation, method.replace('"', ""), !runtime.runtime.config.is_empty());
    output(&response, response_json)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_cancel(runtime: *mut mgread_runtime_handle, request_id: *const c_char) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else { return 1; };
    let Some(request_id) = (unsafe { input(request_id) }) else { return 1; };
    if request_id.is_empty() { return 1; }
    let Ok(mut state) = runtime.runtime.state.lock() else { return 8; };
    if !state.started { return 2; }
    state.cancelled.insert(request_id.to_owned()); 0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_stop(runtime: *mut mgread_runtime_handle) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else { return 1; };
    let Ok(mut state) = runtime.runtime.state.lock() else { return 8; };
    state.started = false; state.cancelled.clear(); 0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_restart(runtime: *mut mgread_runtime_handle) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else { return 1; };
    let Ok(mut state) = runtime.runtime.state.lock() else { return 8; };
    state.started = true; state.cancelled.clear(); state.generation = state.generation.saturating_add(1); 0
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_free_string(value: *mut c_char) {
    if !value.is_null() { unsafe { drop(CString::from_raw(value)); } }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_free(runtime: *mut mgread_runtime_handle) {
    if !runtime.is_null() { unsafe { drop(Box::from_raw(runtime)); } }
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
        unsafe { mgread_runtime_free_string(response); }
        assert_eq!(unsafe { mgread_runtime_cancel(runtime, id.as_ptr()) }, 0);
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, 4);
        assert_eq!(unsafe { mgread_runtime_restart(runtime) }, 0);
        assert_eq!(unsafe { mgread_runtime_invoke(runtime, request.as_ptr(), &mut response) }, 0);
        unsafe { mgread_runtime_free_string(response); mgread_runtime_free(runtime); }
    }
}
