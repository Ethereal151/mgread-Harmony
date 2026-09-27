# OHOS Native Runtime package

This package owns the optional HarmonyOS Native/Rust Runtime bridge. It is
independent from `mgread_plugin_runtime/ohos`, whose Node Runtime and ArkWeb
implementation remains the production default. The Rust library exposes only
the C ABI in `native/rust-runtime/include/mgread_runtime.h`; the C++ layer owns
Node-API threading and Promise conversion.

The package is present in the application HAP for capability probing, but
`PluginRuntime` must continue to select Node Runtime by default. Do not expose
Native source import until the arm64 device smoke test, fixed-plugin
invoke/cancel/restart test, and resource contract tests pass.
