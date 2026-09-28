//! Minimal OHOS Native/Rust Runtime ABI.
//!
//! The public boundary intentionally has no Rust types or allocator ownership.
//! The C++ shim runs these calls away from the ArkTS/UI thread and owns the
//! returned string through `mgread_runtime_free_string`.

use std::collections::HashSet;
use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::sync::{LazyLock, Mutex};

#[path = "../../../../../plugins/sources/aisishuwu-native/src/parsing.rs"]
mod parsing;
#[path = "../../../../../plugins/sources/aisishuwu-native/src/source.rs"]
mod source;

use serde_json::{Value, json};
use base64::Engine;

const MGREAD_RUNTIME_INVALID_ARGUMENT: i32 = 1;
const MGREAD_RUNTIME_TIMEOUT: i32 = 3;
const MGREAD_RUNTIME_CANCELLED: i32 = 4;
const MGREAD_RUNTIME_NETWORK_ERROR: i32 = 5;
const MGREAD_RUNTIME_PLUGIN_ERROR: i32 = 6;
const MGREAD_RUNTIME_RESOURCE_ERROR: i32 = 7;
const MGREAD_RUNTIME_UNSUPPORTED: i32 = 9;

static LAST_ERROR: LazyLock<Mutex<String>> = LazyLock::new(|| Mutex::new(String::new()));

fn set_last_error(value: impl Into<String>) {
    if let Ok(mut error) = LAST_ERROR.lock() {
        *error = value.into();
    }
}

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

fn source_http(request: &Value, proxy: Option<&str>) -> Result<Value, i32> {
    let url = request["url"]
        .as_str()
        .ok_or(MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    let parsed = url::Url::parse(url).map_err(|_| MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    if parsed.scheme() != "https" || parsed.origin().ascii_serialization() != parsing::ORIGIN {
        return Err(MGREAD_RUNTIME_INVALID_ARGUMENT);
    }
    let configured_proxy = match proxy {
        Some(value) => match ureq::Proxy::new(value) {
            Ok(proxy) => Some(proxy),
            Err(error) => {
                set_last_error(format!("invalid configured proxy: {error}"));
                return Err(MGREAD_RUNTIME_INVALID_ARGUMENT);
            }
        },
        None => None,
    };
    let agent = ureq::Agent::config_builder()
        .timeout_global(Some(std::time::Duration::from_secs(20)))
        .proxy(configured_proxy)
        .build()
        .new_agent();
    let mut request_builder = agent.get(url);
    if let Some(headers) = request["headers"].as_object() {
        for (key, value) in headers {
            if let Some(value) = value.as_str() {
                request_builder = request_builder.header(key, value);
            }
        }
    }
    let response = request_builder.call().map_err(|error| {
        let message = format!("request failed for {url}: {error}");
        eprintln!("mgread native source {message}");
        set_last_error(message);
        MGREAD_RUNTIME_NETWORK_ERROR
    })?;
    let status = response.status().as_u16();
    eprintln!("mgread native source response: {url}: {status}");
    if !(200..300).contains(&status) {
        set_last_error(format!("source returned HTTP status {status} for {url}"));
        return Err(MGREAD_RUNTIME_NETWORK_ERROR);
    }
    let body = response
        .into_body()
        .read_to_string()
        .map_err(|error| {
            let message = format!("body read failed for {url}: {error}");
            eprintln!("mgread native source {message}");
            set_last_error(message);
            MGREAD_RUNTIME_NETWORK_ERROR
        })?;
    if body.len() > 4 * 1024 * 1024 {
        set_last_error(format!("source response exceeded 4 MiB for {url}"));
        return Err(MGREAD_RUNTIME_RESOURCE_ERROR);
    }
    Ok(json!({"status": status, "body": body}))
}

fn source_invoke(request_json: &str, cancelled: impl Fn() -> bool, proxy: Option<&str>) -> Result<String, i32> {
    let request: Value = serde_json::from_str(request_json)
        .map_err(|_| MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    let method = request["method"]
        .as_str()
        .ok_or(MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    if !matches!(
        method,
        "discover" | "search" | "searchSuggestions" | "getDetail" | "getChapters" | "getContent"
    ) {
        return Err(MGREAD_RUNTIME_UNSUPPORTED);
    }
    let source_request = request.get("request").cloned().unwrap_or(Value::Null);
    let mut input = json!({"method": method, "request": source_request, "state": null});
    for _ in 0..128 {
        if cancelled() {
            return Err(MGREAD_RUNTIME_CANCELLED);
        }
        let output = source::dispatch(input).map_err(|error| {
            set_last_error(format!("source parser error: {error}"));
            MGREAD_RUNTIME_PLUGIN_ERROR
        })?;
        match output["kind"].as_str() {
            Some("result") => {
                let value = output
                    .get("value")
                    .cloned()
                    .ok_or(MGREAD_RUNTIME_PLUGIN_ERROR)?;
                return serde_json::to_string(&json!({
                    "ok": true,
                    "engine": "ohos-native",
                    "sourceId": "org.mgread.aisishuwu.native",
                    "value": value,
                }))
                .map_err(|_| MGREAD_RUNTIME_RESOURCE_ERROR);
            }
            Some("http") => {
                let requests = output["requests"]
                    .as_array()
                    .ok_or(MGREAD_RUNTIME_PLUGIN_ERROR)?;
                let mut responses = Vec::with_capacity(requests.len());
                for request in requests {
                    if cancelled() {
                        return Err(MGREAD_RUNTIME_CANCELLED);
                    }
                    responses.push(source_http(request, proxy)?);
                }
                input = json!({
                    "method": method,
                    "request": source_request,
                    "state": output.get("state").cloned().unwrap_or(Value::Null),
                    "responses": responses,
                });
            }
            _ => return Err(MGREAD_RUNTIME_PLUGIN_ERROR),
        }
    }
    Err(MGREAD_RUNTIME_TIMEOUT)
}

fn resource_invoke(request_json: &str, cancelled: impl Fn() -> bool, proxy: Option<&str>) -> Result<String, i32> {
    let envelope: Value = serde_json::from_str(request_json)
        .map_err(|_| MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    let request = envelope.get("request").cloned().unwrap_or(Value::Null);
    if cancelled() {
        return Err(MGREAD_RUNTIME_CANCELLED);
    }
    let url = request["url"]
        .as_str()
        .ok_or(MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    let parsed = url::Url::parse(url).map_err(|_| MGREAD_RUNTIME_INVALID_ARGUMENT)?;
    if parsed.scheme() != "https"
        || ![parsing::ORIGIN, "https://img.321cdn.com"].contains(&parsed.origin().ascii_serialization().as_str())
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        set_last_error(format!("resource URL is outside the allowed source origins: {url}"));
        return Err(MGREAD_RUNTIME_INVALID_ARGUMENT);
    }
    let configured_proxy = match proxy {
        Some(value) => Some(ureq::Proxy::new(value).map_err(|_| MGREAD_RUNTIME_INVALID_ARGUMENT)?),
        None => None,
    };
    let agent = ureq::Agent::config_builder()
        .timeout_global(Some(std::time::Duration::from_secs(20)))
        .proxy(configured_proxy)
        .build()
        .new_agent();
    let mut request_builder = agent.get(url);
    if let Some(headers) = request["headers"].as_object() {
        for (key, value) in headers {
            if let Some(value) = value.as_str() {
                request_builder = request_builder.header(key, value);
            }
        }
    }
    let response = request_builder.call().map_err(|error| {
        set_last_error(format!("resource request failed for {url}: {error}"));
        MGREAD_RUNTIME_NETWORK_ERROR
    })?;
    let status = response.status().as_u16();
    if !(200..300).contains(&status) {
        set_last_error(format!("resource returned HTTP status {status} for {url}"));
        return Err(MGREAD_RUNTIME_NETWORK_ERROR);
    }
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .to_owned();
    let bytes = response.into_body().read_to_vec().map_err(|error| {
        set_last_error(format!("resource body read failed for {url}: {error}"));
        MGREAD_RUNTIME_NETWORK_ERROR
    })?;
    if bytes.len() > 8 * 1024 * 1024 {
        set_last_error(format!("resource exceeded 8 MiB for {url}"));
        return Err(MGREAD_RUNTIME_RESOURCE_ERROR);
    }
    serde_json::to_string(&json!({
        "ok": true,
        "engine": "ohos-native",
        "kind": request["kind"].as_str().unwrap_or("resource"),
        "contentType": content_type,
        "bytesBase64": base64::engine::general_purpose::STANDARD.encode(bytes),
    })).map_err(|_| MGREAD_RUNTIME_RESOURCE_ERROR)
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
    let Some(request) = input(request_json) else { return 1; };
    let request_id = json_string(request, "requestId").unwrap_or_default();
    let method = json_string(request, "method").unwrap_or_else(|| "runtime.fixed.invoke".to_owned());
    let (generation, started) = match runtime.runtime.state.lock() {
        Ok(state) => (state.generation, state.started),
        Err(_) => return 8,
    };
    if !started { return 2; }
    let is_cancelled = || {
        runtime.runtime.state.lock().map(|mut state| {
            if !request_id.is_empty() && state.cancelled.remove(&request_id) {
                true
            } else {
                false
            }
        }).unwrap_or(true)
    };
    let proxy = serde_json::from_str::<Value>(&runtime.runtime.config)
        .ok()
        .and_then(|value| value["proxy"].as_str().map(str::to_owned));
    if method == "resource.get" {
        return match resource_invoke(request, is_cancelled, proxy.as_deref()) {
            Ok(response) => output(&response, response_json),
            Err(code) => {
                if LAST_ERROR.lock().map(|error| error.is_empty()).unwrap_or(true) {
                    set_last_error(format!("native resource invocation failed with code {code}"));
                }
                code
            }
        };
    }
    if matches!(method.as_str(), "discover" | "search" | "searchSuggestions" | "getDetail" | "getChapters" | "getContent") {
        return match source_invoke(request, is_cancelled, proxy.as_deref()) {
            Ok(response) => output(&response, response_json),
            Err(code) => {
                if LAST_ERROR.lock().map(|error| error.is_empty()).unwrap_or(true) {
                    set_last_error(format!("native source invocation failed with code {code}"));
                }
                code
            }
        };
    }
    if is_cancelled() { return 4; }
    let response = format!("{{\"ok\":true,\"abiVersion\":1,\"generation\":{},\"method\":\"{}\",\"configPresent\":{}}}", generation, method.replace('"', ""), !runtime.runtime.config.is_empty());
    output(&response, response_json)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_last_error(response_json: *mut *mut c_char) -> i32 {
    let Some(response_json) = (unsafe { response_json.as_mut() }) else { return 1; };
    let error = LAST_ERROR.lock().map(|value| value.clone()).unwrap_or_default();
    output(&error, response_json)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mgread_runtime_cancel(runtime: *mut mgread_runtime_handle, request_id: *const c_char) -> i32 {
    let Some(runtime) = (unsafe { runtime.as_ref() }) else { return 1; };
    let Some(request_id) = input(request_id) else { return 1; };
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

    #[test]
    #[ignore = "requires live access to www.alicesw.com"]
    fn live_alice_source_chain_is_executable() {
        fn call(method: &str, request: Value) -> Value {
            let envelope = json!({"requestId":"live","method":method,"request":request});
            let response = source_invoke(&envelope.to_string(), || false, None)
                .expect("live Alice source request");
            let value: Value = serde_json::from_str(&response).expect("valid source JSON");
            assert_eq!(value["ok"], true);
            assert_eq!(value["sourceId"], "org.mgread.aisishuwu.native");
            value["value"].clone()
        }

        let root = call(
            "discover",
            json!({"target":null,"cursor":null,"collectionId":null,"pageSize":12}),
        );
        let items = root["document"]["components"][0]["items"]
            .as_array()
            .expect("discovery items");
        let content = items[0]["content"].clone();
        let id = content["id"].as_str().expect("content id").to_owned();
        let title = content["title"].as_str().expect("content title").to_owned();
        let search = call("search", json!({"query":title,"cursor":null,"pageSize":10}));
        assert!(!search["items"].as_array().expect("search items").is_empty());
        let detail = call("getDetail", json!({"id":id}));
        assert_eq!(detail["id"], id);
        let chapters = call("getChapters", json!({"id":id}));
        let chapter = chapters["items"].as_array().expect("chapters")[0].clone();
        let body = call(
            "getContent",
            json!({"id":id,"chapterId":chapter["id"].clone()}),
        );
        assert_eq!(body["contentKind"], "novel");
        assert!(!body["text"].as_str().expect("novel text").trim().is_empty());
    }
}
