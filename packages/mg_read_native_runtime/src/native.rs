//! One initialization ABI call per DLL in the shared worker. All later traffic
//! uses the plugin HTTP listener. Libraries remain pinned until process exit.
use crate::{
    catalog::{Manifest, hash},
    error::{Error, Result, invalid},
};
use libloading::Library;
use mgread_native_abi::{ABI_VERSION, InitResult};
use serde_json::{Value, json};
use std::{mem::ManuallyDrop, path::Path};

#[cfg(target_env = "ohos")]
mod ohos_loader {
    use super::Error;
    use libloading::os::unix::Library as UnixLibrary;
    use std::{
        ffi::CString,
        os::raw::{c_char, c_int, c_void},
        path::Path,
    };

    const NS_NAME_MAX: usize = 255;
    const CREATE_INHERIT_DEFAULT: c_int = 1;
    const EEXIST: c_int = 17;
    const RTLD_NOW: c_int = 2;
    const RTLD_LOCAL: c_int = 0;
    const PRIVATE_NAMESPACE: &str = "nweb_ns_legacy";

    #[repr(C)]
    struct DlNamespace {
        name: [c_char; NS_NAME_MAX + 1],
    }

    type DlnsInit = unsafe extern "C" fn(*mut DlNamespace, *const c_char);
    type DlnsGet = unsafe extern "C" fn(*const c_char, *mut DlNamespace) -> c_int;
    type DlnsCreate2 = unsafe extern "C" fn(*mut DlNamespace, *const c_char, c_int) -> c_int;
    type DlopenNs = unsafe extern "C" fn(*mut DlNamespace, *const c_char, c_int) -> *mut c_void;
    type Dlerror = unsafe extern "C" fn() -> *const c_char;

    unsafe fn loader_error(dlerror: Option<Dlerror>) -> String {
        let Some(dlerror) = dlerror else {
            return "unknown dynamic loader error".into();
        };
        let message = unsafe { dlerror() };
        if message.is_null() {
            return "unknown dynamic loader error".into();
        }
        unsafe { std::ffi::CStr::from_ptr(message) }
            .to_string_lossy()
            .into_owned()
    }

    pub(super) unsafe fn load(path: &Path) -> Result<libloading::Library, Error> {
        let symbols = UnixLibrary::this();
        let init: DlnsInit = *unsafe { symbols.get(b"dlns_init\0") }.map_err(|_| {
            Error::new(
                "plugin_load_failed",
                "OpenHarmony namespace loader is unavailable",
            )
        })?;
        let get: DlnsGet = *unsafe { symbols.get(b"dlns_get\0") }.map_err(|_| {
            Error::new(
                "plugin_load_failed",
                "OpenHarmony namespace loader is unavailable",
            )
        })?;
        let create2: DlnsCreate2 = *unsafe { symbols.get(b"dlns_create2\0") }
            .map_err(|_| {
                Error::new(
                    "plugin_load_failed",
                    "OpenHarmony namespace loader is unavailable",
                )
            })?;
        let open_ns: DlopenNs = *unsafe { symbols.get(b"dlopen_ns\0") }.map_err(|_| {
            Error::new(
                "plugin_load_failed",
                "OpenHarmony namespace loader is unavailable",
            )
            })?;
        let dlerror: Option<Dlerror> = unsafe { symbols.get(b"dlerror\0") }
            .ok()
            .map(|symbol| *symbol);

        let parent = path.parent().ok_or_else(|| {
            Error::new("plugin_load_failed", "Native binary has no load directory")
        })?;
        let parent = CString::new(parent.to_string_lossy().as_bytes()).map_err(|_| {
            Error::new("plugin_load_failed", "Native binary path contains a NUL byte")
        })?;
        let filename = path.file_name().and_then(|value| value.to_str()).ok_or_else(|| {
            Error::new("plugin_load_failed", "Native binary filename is invalid")
        })?;
        let filename = CString::new(filename.as_bytes()).map_err(|_| {
            Error::new("plugin_load_failed", "Native binary path contains a NUL byte")
        })?;

        // OpenHarmony's application namespace policy grants the runtime this
        // platform-provided private namespace. It is shared by native
        // plugins, so loading remains independent of any source identity.
        let name = CString::new(PRIVATE_NAMESPACE).expect("namespace name is ASCII");
        let mut namespace = std::mem::MaybeUninit::<DlNamespace>::zeroed();
        unsafe { init(namespace.as_mut_ptr(), name.as_ptr()) };
        let namespace = unsafe { namespace.assume_init_mut() };

        let result = unsafe { create2(namespace, parent.as_ptr(), CREATE_INHERIT_DEFAULT) };
        if result != 0 && result != EEXIST {
            return Err(Error {
                code: "plugin_load_failed".into(),
                message: format!("OpenHarmony rejected the native library namespace: {result}"),
            });
        }
        if result == EEXIST {
            let result = unsafe { get(name.as_ptr(), namespace) };
            if result != 0 {
                return Err(Error {
                    code: "plugin_load_failed".into(),
                    message: format!(
                        "OpenHarmony could not open the native library namespace: {result}"
                    ),
                });
            }
        }
        // dlopen_ns resolves a library name through the namespace search path
        // configured above. Passing the absolute source path bypasses that
        // contract and is rejected by the application namespace on device.
        let handle = unsafe { open_ns(namespace, filename.as_ptr(), RTLD_NOW | RTLD_LOCAL) };
        if handle.is_null() {
            return Err(Error {
                code: "plugin_load_failed".into(),
                message: format!(
                    "OpenHarmony rejected the native library path: {}",
                    unsafe { loader_error(dlerror) }
                ),
            });
        }

        Ok(libloading::Library::from(unsafe { UnixLibrary::from_raw(handle) }))
    }
}

#[cfg(target_env = "ohos")]
fn bundled_library_for_target(target_path: &str, directory: &Path) -> Result<std::path::PathBuf> {
    if !directory.is_absolute() {
        return Err(Error::new(
            "plugin_load_failed",
            "OHOS native library directory is unavailable",
        ));
    }
    let filename = Path::new(target_path)
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| Error::new("plugin_load_failed", "Native target path is invalid"))?;
    Ok(directory.join(filename))
}

pub struct NativePlugin {
    _library: ManuallyDrop<Library>,
    pub endpoint: Value,
}
impl NativePlugin {
    pub fn load(
        path: &Path,
        manifest: &Manifest,
        config: Value,
        native_library_dir: Option<&Path>,
    ) -> Result<Self> {
        #[cfg(not(target_env = "ohos"))]
        let _ = native_library_dir;
        if manifest.abi != ABI_VERSION {
            return Err(Error::new(
                "unsupported_abi",
                "Reinstall this source using an ABI v3 archive",
            ));
        }
        if hash(&std::fs::read(path)?) != manifest.targets[crate::catalog::target()].sha256 {
            return Err(invalid("Native binary integrity failed"));
        }
        #[cfg(target_env = "ohos")]
        let load_path = bundled_library_for_target(
            &manifest.targets[crate::catalog::target()].path,
            native_library_dir.ok_or_else(|| {
                Error::new(
                    "plugin_load_failed",
                    "OHOS application native library directory is unavailable",
                )
            })?,
        )?;
        #[cfg(not(target_env = "ohos"))]
        let load_path = path.to_path_buf();
        unsafe {
            #[cfg(target_env = "ohos")]
            let loaded = ohos_loader::load(&load_path);
            #[cfg(not(target_env = "ohos"))]
            let loaded = Library::new(&load_path);
            let library = ManuallyDrop::new(loaded.map_err(|error| Error {
                code: "plugin_load_failed".into(),
                message: format!("Native binary could not be loaded: {error}"),
            })?);
            let init: libloading::Symbol<unsafe extern "C" fn(*const u8, usize) -> InitResult> =
                library
                    .get(b"mg_source_init_v3\0")
                    .map_err(|_| invalid("Missing source initialization entry"))?;
            let input = serde_json::to_vec(&config)?;
            let ready = init(input.as_ptr(), input.len());
            if ready.version != ABI_VERSION
                || ready.status != 0
                || ready.port == 0
                || ready.reserved != 0
            {
                return Err(Error::new(
                    "plugin_init_failed",
                    "Native source initialization failed",
                ));
            }
            Ok(Self {
                _library: library,
                endpoint: json!({"pluginId":manifest.id,"sourceName":manifest.name,"generation":config["generation"],"port":ready.port,"controlToken":config["controlToken"]}),
            })
        }
    }
    pub async fn shutdown(&self, client: &reqwest::Client) -> Result<()> {
        let port = self.endpoint["port"].as_u64().unwrap() as u16;
        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            client
                .post(format!("http://127.0.0.1:{port}/shutdown"))
                .bearer_auth(self.endpoint["controlToken"].as_str().unwrap())
                .send()
                .await
                .map_err(|_| Error::new("shutdown_failed", "Plugin HTTP shutdown failed"))?
                .error_for_status()
                .map_err(|_| Error::new("shutdown_failed", "Plugin HTTP shutdown rejected"))?;
            // The HTTP response only acknowledges stop intent. Wait for the
            // listener to close before reporting cooperative service shutdown.
            while tokio::net::TcpStream::connect(("127.0.0.1", port))
                .await
                .is_ok()
            {
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
            }
            Ok(())
        })
        .await
        .map_err(|_| Error::new("shutdown_failed", "Plugin listener did not stop"))?
    }
}

pub fn init_config(
    root: &Path,
    manifest: &Manifest,
    generation: &str,
    control_token: &str,
    proxy: Option<String>,
    test_mode: bool,
) -> Result<Value> {
    let plugin = root.join("plugins").join(&manifest.id);
    let cache = plugin.join("cache");
    for path in [&plugin, &cache] {
        std::fs::create_dir_all(path)?;
        if std::fs::symlink_metadata(path)?.file_type().is_symlink()
            || !path.canonicalize()?.starts_with(root)
        {
            return Err(invalid("Invalid plugin cache directory"));
        }
    }
    Ok(
        json!({"pluginId":manifest.id,"sourceName":manifest.name,"capabilities":manifest.capabilities,"generation":generation,"controlToken":control_token,"cacheDir":cache.canonicalize()?,"upstreamProxy":proxy,"testMode":test_mode}),
    )
}
