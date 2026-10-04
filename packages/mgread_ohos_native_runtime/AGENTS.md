# OHOS Native Runtime package

This package owns the optional HarmonyOS Native/Rust Runtime bridge for both
`arm64` and `x64`. It is independent from `mgread_plugin_runtime/ohos`, which
owns the embedded Node Runtime and ArkWeb host. The Rust library exposes only
the C ABI in `native/rust-runtime/include/mgread_runtime.h`; the C++ layer owns
Node-API threading and Promise conversion. Architecture selection belongs to
the OHOS build adapters and must produce a matching Rust artifact and ABI filter.

Node Runtime remains the default for JavaScript sources. Keep Native source
selection routed through the shared `PluginRuntime` Facade. Before publishing
an ABI build, run that architecture's Native fixed-plugin lifecycle and source
resource integration tests in addition to the Node Runtime smoke and source
fixture tests.
