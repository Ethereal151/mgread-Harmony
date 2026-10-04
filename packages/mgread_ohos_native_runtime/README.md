# MgRead OHOS Native Runtime

This is the Native/Rust Runtime boundary for HarmonyOS on both arm64 and x64.
The selected ABI's Rust shared library is linked into the HAP alongside the
embedded Node Runtime. JavaScript sources continue to use Node; Native sources
are routed by the existing Runtime Facade according to their engine metadata.

The boundary is:

`Flutter -> MethodChannel -> ArkTS/Node-API -> C++ worker shim -> Rust C ABI`

The Rust side owns an opaque handle and returns only bounded UTF-8 JSON. It
does not expose Rust pointers, allocators, threads, or file paths. The OHOS
Rust library is source-neutral: it does not ship or auto-register a built-in
data source, but it can load a user-imported `engine=native` `.mgplugin` whose
manifest contains the selected OHOS ABI target and whose library passes the
same ABI and SHA-256 checks as Android and Windows. The fixed-plugin lifecycle
remains available as an ABI regression test.

The package expects the OpenHarmony NDK to provide `napi/native_api.h`. The
OHOS release and integration adapters compile the pinned Rust target selected
for the HAP ABI and pass it to CMake through `MGREAD_RUST_RUNTIME_LIB` and
`MGREAD_RUST_RUNTIME_INCLUDE`. CMake retains an explicit `unsupported` stub for
direct builds that do not supply a matching Rust artifact; production and
integration builds must supply the selected ABI's library.
