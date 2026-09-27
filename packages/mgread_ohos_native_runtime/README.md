# MgRead OHOS Native Runtime skeleton

This is the staged, opt-in Native/Rust Runtime boundary for HarmonyOS. Its HAR
is linked into the main HAP so the arm64 smoke path can be verified on a real
device, but the existing Node Runtime remains the default and no installed
Node/ArkWeb data source changes engine.

The minimum boundary is:

`Flutter -> MethodChannel -> ArkTS/Node-API -> C++ worker shim -> Rust C ABI`

The Rust side owns an opaque handle and returns only bounded UTF-8 JSON. It
does not expose Rust pointers, allocators, threads, or file paths. The current
fixed-plugin implementation is intentionally a lifecycle/ABI smoke core;
HTTP, cookies, resources, HLS, and a real source are follow-up capabilities and
must not be advertised as available until their tests are added.

The package expects the OpenHarmony NDK to provide `napi/native_api.h`. When
`MGREAD_RUST_RUNTIME_LIB` and `MGREAD_RUST_RUNTIME_INCLUDE` are supplied to
CMake it builds the arm64 Rust bridge; otherwise it builds an explicit
`unsupported` stub, preserving ordinary Node Runtime builds.
