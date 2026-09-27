# MgRead OHOS Native Runtime

This is the staged, opt-in Native/Rust Runtime boundary for HarmonyOS. Its HAR
is linked into the main HAP so the arm64 smoke path can be verified on a real
device, but the existing Node Runtime remains the default and no installed
Node/ArkWeb data source changes engine.

The boundary is:

`Flutter -> MethodChannel -> ArkTS/Node-API -> C++ worker shim -> Rust C ABI`

The Rust side owns an opaque handle and returns only bounded UTF-8 JSON. It
does not expose Rust pointers, allocators, threads, or file paths. The Native
source path now executes the Alice novel source through the same source parser
and stable IDs used by `plugins/sources/aisishuwu-native`, with Rust-owned HTTPS
GETs, bounded HTML responses, and cancellation checks between requests. The
source-scoped image resource fetches, and cancellation checks between requests.
The fixed-plugin lifecycle remains available as an ABI regression test.

The package expects the OpenHarmony NDK to provide `napi/native_api.h`. When
`MGREAD_RUST_RUNTIME_LIB` and `MGREAD_RUST_RUNTIME_INCLUDE` are supplied to
CMake it builds the arm64 Rust bridge; otherwise it builds an explicit
`unsupported` stub, preserving ordinary Node Runtime builds. x86_64 remains an
explicit unsupported target until a Rust TLS build and emulator run are
available.
