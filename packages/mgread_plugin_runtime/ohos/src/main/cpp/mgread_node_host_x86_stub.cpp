#include <cstddef>

#include <napi/native_api.h>

namespace {

constexpr char kMessage[] =
    "The embedded Node Runtime is arm64-only; use an OpenHarmony arm64 device.";

napi_value ThrowUnavailable(napi_env env, napi_callback_info) {
  napi_throw_error(env, "runtime_architecture_unavailable", kMessage);
  return nullptr;
}

napi_value Cancel(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_boolean(env, false, &result);
  return result;
}

napi_value SetProgress(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value SetBrowserSessionCallback(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value ResolveBrowserSession(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value CancelBrowserSession(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value ClearBrowserSessionCallback(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value Dispose(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

napi_value RuntimeVersion(napi_env env, napi_callback_info) {
  napi_value result;
  napi_create_string_utf8(env, "24.16.0", NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value NativeNodeHostAvailable(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_boolean(env, false, &result);
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"initialize", nullptr, ThrowUnavailable, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"invoke", nullptr, ThrowUnavailable, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"invokeAsync", nullptr, ThrowUnavailable, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"cancelInvocation", nullptr, Cancel, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"runtimePaths", nullptr, ThrowUnavailable, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"materializeTransfer", nullptr, ThrowUnavailable, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"restart", nullptr, ThrowUnavailable, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"setProgressCallback", nullptr, SetProgress, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"setBrowserSessionCallback", nullptr, SetBrowserSessionCallback, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"resolveBrowserSession", nullptr, ResolveBrowserSession, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"cancelBrowserSession", nullptr, CancelBrowserSession, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"clearBrowserSessionCallback", nullptr, ClearBrowserSessionCallback, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"dispose", nullptr, Dispose, nullptr, nullptr, nullptr, napi_default,
       nullptr},
      {"runtimeVersion", nullptr, RuntimeVersion, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"nativeNodeHostAvailable", nullptr, NativeNodeHostAvailable, nullptr,
       nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]),
                         properties);
  return exports;
}

}  // namespace

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "mgread_node_host",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" __attribute__((constructor)) void RegisterMgReadNodeHost() {
  napi_module_register(&g_module);
}
