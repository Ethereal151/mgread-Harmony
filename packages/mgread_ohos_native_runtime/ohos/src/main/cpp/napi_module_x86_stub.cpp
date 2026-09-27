#include <napi/native_api.h>

namespace {
napi_value Unsupported(napi_env env, napi_callback_info) {
  napi_value result;
  napi_create_int32(env, 9, &result);
  return result;
}

napi_value Version(napi_env env, napi_callback_info) {
  napi_value result;
  napi_create_string_utf8(env, "mgread-ohos-native-runtime/0.1.0 abi=1 unsupported", NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"create", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"start", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"start", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"invoke", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cancel", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stop", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"restart", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dispose", nullptr, Unsupported, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}
}  // namespace

static napi_module g_module = {
    .nm_version = 1, .nm_flags = 0, .nm_filename = nullptr,
    .nm_register_func = Init, .nm_modname = "mgread_ohos_native_runtime",
    .nm_priv = nullptr, .reserved = {nullptr, nullptr, nullptr, nullptr},
};

extern "C" __attribute__((constructor)) void RegisterMgReadOhosNativeRuntime() {
  napi_module_register(&g_module);
}
