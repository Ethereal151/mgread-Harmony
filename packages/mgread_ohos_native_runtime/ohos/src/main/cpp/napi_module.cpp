#include <napi/native_api.h>

#include <memory>
#include <mutex>
#include <string>

#include "runtime_bridge.h"

namespace {
std::shared_ptr<RuntimeBridge> g_runtime;
std::mutex g_runtime_mutex;

std::string ReadString(napi_env env, napi_value value) {
  size_t length = 0;
  napi_get_value_string_utf8(env, value, nullptr, 0, &length);
  std::string result(length, '\0');
  napi_get_value_string_utf8(env, value, result.data(), length + 1, &length);
  return result;
}

napi_value Code(napi_env env, int code) {
  napi_value result;
  napi_create_int32(env, code, &result);
  return result;
}

napi_value Version(napi_env env, napi_callback_info) {
  napi_value result;
  napi_create_string_utf8(env, mgread_runtime_version(), NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value Create(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 1) { napi_throw_error(env, "invalid_argument", "create expects config JSON"); return nullptr; }
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  g_runtime = std::make_shared<RuntimeBridge>(ReadString(env, argv[0]));
  return Code(env, g_runtime->Start());
}

napi_value Start(napi_env env, napi_callback_info) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  return Code(env, g_runtime == nullptr ? MGREAD_RUNTIME_NOT_INITIALIZED : g_runtime->Start());
}
napi_value Stop(napi_env env, napi_callback_info) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  return Code(env, g_runtime == nullptr ? MGREAD_RUNTIME_NOT_INITIALIZED : g_runtime->Stop());
}
napi_value Restart(napi_env env, napi_callback_info) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  return Code(env, g_runtime == nullptr ? MGREAD_RUNTIME_NOT_INITIALIZED : g_runtime->Restart());
}

napi_value Cancel(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 1) { napi_throw_error(env, "invalid_argument", "cancel expects request ID"); return nullptr; }
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  return Code(env, g_runtime == nullptr ? MGREAD_RUNTIME_NOT_INITIALIZED : g_runtime->Cancel(ReadString(env, argv[0])));
}

napi_value LastError(napi_env env, napi_callback_info) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  const std::string error = g_runtime == nullptr ? std::string() : g_runtime->LastError();
  napi_value result;
  napi_create_string_utf8(env, error.c_str(), NAPI_AUTO_LENGTH, &result);
  return result;
}

struct InvokeWork { napi_async_work work = nullptr; napi_deferred deferred = nullptr; std::shared_ptr<RuntimeBridge> runtime; std::string request; std::string response; int code = MGREAD_RUNTIME_NOT_INITIALIZED; };

void ExecuteInvoke(napi_env, void* data) {
  auto* work = static_cast<InvokeWork*>(data);
  if (work->runtime != nullptr) work->code = work->runtime->Invoke(work->request, &work->response);
}

void CompleteInvoke(napi_env env, napi_status status, void* data) {
  auto* work = static_cast<InvokeWork*>(data);
  if (status != napi_ok || work->code != MGREAD_RUNTIME_OK) {
    napi_value error; napi_create_int32(env, work->code, &error);
    napi_reject_deferred(env, work->deferred, error);
  } else {
    napi_value value; napi_create_string_utf8(env, work->response.c_str(), NAPI_AUTO_LENGTH, &value);
    napi_resolve_deferred(env, work->deferred, value);
  }
  napi_delete_async_work(env, work->work);
  delete work;
}

napi_value Invoke(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 1) { napi_throw_error(env, "invalid_argument", "invoke expects request JSON"); return nullptr; }
  auto* work = new InvokeWork();
  {
    std::lock_guard<std::mutex> lock(g_runtime_mutex);
    work->runtime = g_runtime;
  }
  work->request = ReadString(env, argv[0]);
  napi_value promise;
  napi_create_promise(env, &work->deferred, &promise);
  napi_value name; napi_create_string_utf8(env, "mgread_native_invoke", NAPI_AUTO_LENGTH, &name);
  napi_create_async_work(env, nullptr, name, ExecuteInvoke, CompleteInvoke, work, &work->work);
  napi_queue_async_work(env, work->work);
  return promise;
}

napi_value Dispose(napi_env env, napi_callback_info) {
  std::lock_guard<std::mutex> lock(g_runtime_mutex);
  g_runtime.reset();
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"create", nullptr, Create, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"invoke", nullptr, Invoke, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"lastError", nullptr, LastError, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"cancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"restart", nullptr, Restart, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"dispose", nullptr, Dispose, nullptr, nullptr, nullptr, napi_default, nullptr},
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
