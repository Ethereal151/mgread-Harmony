#include <condition_variable>
#include <chrono>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <set>
#include <thread>
#include <utility>
#include <vector>

#include <uv.h>
#include "cppgc/platform.h"
#include "node.h"
#include <napi/native_api.h>

namespace {

constexpr char kNodeVersion[] = "24.16.0";

std::string Utf8(napi_env env, napi_value value) {
  size_t length = 0;
  napi_get_value_string_utf8(env, value, nullptr, 0, &length);
  std::string result(length, '\0');
  napi_get_value_string_utf8(env, value, result.data(), result.size() + 1, &length);
  result.resize(length);
  return result;
}

napi_value StringValue(napi_env env, const std::string& value) {
  napi_value result;
  napi_create_string_utf8(env, value.data(), value.size(), &result);
  return result;
}

class NodeHost {
 public:
  NodeHost() = default;
  ~NodeHost() { Dispose(); }

  void Initialize(std::string runtime_root, std::string data_root, std::string inbox_root) {
    auto completion = std::make_shared<std::promise<void>>();
    auto future = completion->get_future();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (disposed_ && !thread_.joinable()) {
        // A validated plugin import restarts the same process-scoped host.
        // Disposal has already joined the old VM thread at this point.
        disposed_ = false;
        cancellation_ids_.clear();
      }
      if (disposed_) throw std::runtime_error("runtime_disposed");
      if (!thread_.joinable()) thread_ = std::thread(&NodeHost::Run, this);
      EnqueueLocked([this, runtime_root = std::move(runtime_root), data_root = std::move(data_root),
                     inbox_root = std::move(inbox_root), completion]() mutable {
        try {
          if (initialization_error_) std::rethrow_exception(initialization_error_);
          if (!initialized_) {
            try {
              Start(runtime_root, data_root, inbox_root);
            } catch (...) {
              initialization_error_ = std::current_exception();
              throw;
            }
          }
          completion->set_value();
        } catch (...) {
          try { completion->set_exception(std::current_exception()); } catch (...) {}
        }
      });
    }
    future.get();
  }

  std::string Invoke(const std::string& request_id, const std::string& method,
                     const std::string& params_json, double deadline) {
    auto completion = std::make_shared<std::promise<std::string>>();
    auto future = completion->get_future();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (disposed_) throw std::runtime_error("runtime_disposed");
      if (!thread_.joinable()) throw std::runtime_error("runtime_not_initialized");
      EnqueueLocked([this, request_id, method, params_json, deadline,
                     completion]() mutable {
        try {
          completion->set_value(Call("__mgreadInvokeJson", {request_id, method, params_json}, deadline, request_id));
          std::lock_guard<std::mutex> lock(mutex_);
          cancellation_ids_.erase(request_id);
        }
        catch (...) {
          std::lock_guard<std::mutex> lock(mutex_);
          cancellation_ids_.erase(request_id);
          try { completion->set_exception(std::current_exception()); } catch (...) {}
        }
      });
    }
    return future.get();
  }

  bool Cancel(const std::string& request_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (disposed_ || !thread_.joinable()) return false;
    cancellation_ids_.insert(request_id);
    return true;
  }

  std::string RuntimePaths() {
    std::lock_guard<std::mutex> lock(mutex_);
    return "{\"dataRoot\":\"" + JsonEscape(data_root_) +
      "\",\"inboxRoot\":\"" + JsonEscape(inbox_root_) + "\"}";
  }

  std::string MaterializeTransfer(const std::string& token,
                                  const std::string& destination) {
    auto completion = std::make_shared<std::promise<std::string>>();
    auto future = completion->get_future();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (disposed_) throw std::runtime_error("runtime_disposed");
      if (!thread_.joinable()) throw std::runtime_error("runtime_not_initialized");
      EnqueueLocked([this, token, destination, completion]() mutable {
        try {
          completion->set_value(Call("__mgreadMaterializeTransferJson", {token, destination}, 0));
        } catch (...) {
          try { completion->set_exception(std::current_exception()); } catch (...) {}
        }
      });
    }
    return future.get();
  }

  std::string Restart() {
    auto completion = std::make_shared<std::promise<std::string>>();
    auto future = completion->get_future();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (disposed_ || !thread_.joinable() || !initialized_) {
        throw std::runtime_error("runtime_not_initialized");
      }
      EnqueueLocked([this, completion]() mutable {
        try {
          completion->set_value(Call("__mgreadRestartCoreJson", {data_root_, inbox_root_}, 0));
        } catch (...) {
          try { completion->set_exception(std::current_exception()); } catch (...) {}
        }
      });
    }
    return future.get();
  }

  void Dispose() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (disposed_) return;
      disposed_ = true;
      if (thread_.joinable()) {
        queue_.emplace_back([this] {
          if (initialized_) {
            try { Call("__mgreadStopJson", {}, 0); } catch (...) {}
          }
        });
        condition_.notify_one();
      }
    }
    if (thread_.joinable()) thread_.join();
  }

  void SetProgress(napi_env env, napi_value callback) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    if (progress_function_tsfn_ != nullptr) {
      napi_release_threadsafe_function(progress_function_tsfn_, napi_tsfn_abort);
      progress_function_tsfn_ = nullptr;
    }
    if (progress_function_ != nullptr) {
      napi_delete_reference(env, progress_function_);
      progress_function_ = nullptr;
    }
    napi_create_reference(env, callback, 1, &progress_function_);
    napi_value resource_name;
    napi_create_string_utf8(env, "mgread-node-host", NAPI_AUTO_LENGTH, &resource_name);
    napi_create_threadsafe_function(env, callback, nullptr, resource_name, 32, 1, this,
      nullptr, this, &NodeHost::ProgressOnJs, &progress_function_tsfn_);
  }

  void ReportProgress(const std::string& payload) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    if (progress_function_tsfn_ != nullptr) {
      auto* copy = new std::string(payload);
      if (napi_call_threadsafe_function(progress_function_tsfn_, copy, napi_tsfn_nonblocking) != napi_ok) {
        delete copy;
      }
    }
  }

  void ClearProgress(napi_env env) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    if (progress_function_tsfn_ != nullptr) {
      napi_release_threadsafe_function(progress_function_tsfn_, napi_tsfn_abort);
      progress_function_tsfn_ = nullptr;
    }
    if (progress_function_ != nullptr) {
      napi_delete_reference(env, progress_function_);
      progress_function_ = nullptr;
    }
  }

 private:
  void EnqueueLocked(std::function<void()> task) {
    queue_.emplace_back(std::move(task));
    condition_.notify_one();
  }

  void Run() {
    for (;;) {
      std::function<void()> task;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock, [this] { return !queue_.empty() || disposed_; });
        if (queue_.empty() && disposed_) break;
        task = std::move(queue_.front());
        queue_.pop_front();
      }
      task();
    }
    if (initialized_) Stop();
  }

  void Start(const std::string& runtime_root, const std::string& data_root,
             const std::string& inbox_root) {
    runtime_root_ = runtime_root;
    data_root_ = data_root;
    inbox_root_ = inbox_root;
    std::vector<std::string> args = {"mgread-node-host", "--no-warnings",
      // HarmonyOS enforces W^X and rejects the RWX code range V8 normally
      // reserves. V8 exposes no runtime toggle for that choice on this version,
      // so the only supported route is to disable runtime executable memory.
      "--jitless"};
    initialization_ = node::InitializeOncePerProcess(args, {
      node::ProcessInitializationFlags::kNoInitializeV8,
      node::ProcessInitializationFlags::kNoInitializeNodeV8Platform,
      node::ProcessInitializationFlags::kDisableNodeOptionsEnv,
      node::ProcessInitializationFlags::kNoInitializeCppgc,
      node::ProcessInitializationFlags::kNoDefaultSignalHandling,
    });
    if (initialization_->early_return() || !initialization_->errors().empty()) {
      throw std::runtime_error("node_process_initialization_failed");
    }
    platform_ = node::MultiIsolatePlatform::Create(4);
    v8::V8::InitializePlatform(platform_.get());
    cppgc::InitializeProcess(platform_->GetPageAllocator());
    v8::V8::Initialize();
    std::vector<std::string> errors;
    setup_ = node::CommonEnvironmentSetup::Create(platform_.get(), &errors,
      initialization_->args(), initialization_->exec_args(),
      static_cast<node::EnvironmentFlags::Flags>(
        node::EnvironmentFlags::kNoCreateInspector |
        node::EnvironmentFlags::kNoGlobalSearchPaths |
        node::EnvironmentFlags::kNoNativeAddons));
    if (!setup_ || !errors.empty()) throw std::runtime_error("node_environment_creation_failed");
    isolate_ = setup_->isolate();
    env_ = setup_->env();
    v8::Locker locker(isolate_);
    v8::Isolate::Scope isolate_scope(isolate_);
    v8::HandleScope handle_scope(isolate_);
    v8::Context::Scope context_scope(setup_->context());
    node::SetProcessExitHandler(env_, [](node::Environment* environment, int) { node::Stop(environment); });
    InstallProgressCallback();
    const std::string dist = runtime_root + "/dist/desktop-runtime.js";
    const std::string bootstrap =
      "globalThis.__mgreadStartCoreJson = async (dataRoot, inboxRoot) => {"
      " const fs = process.getBuiltinModule('fs');"
      " let mod; try { mod = process.getBuiltinModule('module').createRequire(" + Quote(dist) + ")(" + Quote(dist) + "); }"
      " catch (e) { const state = fs.existsSync(" + Quote(dist) + ") ? String(fs.statSync(" + Quote(dist) + ").size) : 'missing';"
      " throw new Error('runtime_load:' + state + ':' + String(e?.stack ?? e)); }"
      " const core = new mod.DesktopRuntime({dataRoot, pluginImportInboxRoot: inboxRoot, embedded: true, debugHttpAllowed: true, "
      " onProgress: p => globalThis.__mgreadReportProgress(JSON.stringify(p))});"
      " await core.start(); const hello = await core.invokeEmbedded('runtime.hello', {});"
      " if (!hello.ok) throw new Error('runtime_hello_failed'); globalThis.__mgreadCore = core; return JSON.stringify({ok:true}); };"
      " const active = new Map();"
      " globalThis.__mgreadInvokeJson = async (id, method, params, deadline) => {"
      " const c = new AbortController(); active.set(id,c); try {"
      " return JSON.stringify(await globalThis.__mgreadCore.invokeEmbedded(method, JSON.parse(params), deadline, c.signal));"
      " } catch (e) { return JSON.stringify({ok:false,error:{code:'internal',message:String(e?.message ?? e)}}); }"
      " finally { active.delete(id); } };"
      " globalThis.__mgreadCancelJson = id => { const c=active.get(id); if (!c) return false; c.abort(); return true; };"
      " globalThis.__mgreadMaterializeTransferJson = async (token, destination) => {"
      " return JSON.stringify(await globalThis.__mgreadCore.materializeTransferEmbedded(token, destination)); };"
      " globalThis.__mgreadRestartCoreJson = async (dataRoot, inboxRoot) => {"
      " if (globalThis.__mgreadCore) await globalThis.__mgreadCore.stop();"
      " return globalThis.__mgreadStartCoreJson(dataRoot, inboxRoot); };"
      " globalThis.__mgreadStopJson = async () => { if (globalThis.__mgreadCore) await globalThis.__mgreadCore.stop(); globalThis.__mgreadCore=undefined; return JSON.stringify({ok:true}); };";
    node::ModuleData entry;
    entry.set_source(bootstrap);
    entry.set_format(node::ModuleFormat::kModule);
    entry.set_resource_name("embedded:mgread-ohos-bootstrap.mjs");
    if (node::LoadEnvironment(env_, &entry).IsEmpty()) throw std::runtime_error("node_bootstrap_failed");
    Call("__mgreadStartCoreJson", {data_root, inbox_root}, 0);
    initialized_ = true;
  }

  std::string Call(const std::string& function, const std::vector<std::string>& strings,
                   double number, const std::string& cancellable_request = {}) {
    v8::Locker locker(isolate_);
    v8::Isolate::Scope isolate_scope(isolate_);
    v8::HandleScope handle_scope(isolate_);
    v8::Context::Scope context_scope(setup_->context());
    v8::Local<v8::Value> property;
    if (!setup_->context()->Global()->Get(setup_->context(), ToV8(function)).ToLocal(&property) || !property->IsFunction()) {
      throw std::runtime_error("node_global_function_missing");
    }
    std::vector<v8::Local<v8::Value>> values;
    for (const auto& value : strings) values.push_back(ToV8(value));
    if (number != 0) values.push_back(v8::Number::New(isolate_, number));
    v8::Local<v8::Value> result;
    if (!property.As<v8::Function>()->Call(setup_->context(), setup_->context()->Global(), values.size(), values.data()).ToLocal(&result)) {
      throw std::runtime_error("node_call_failed");
    }
    return Await(result, cancellable_request);
  }

  std::string Await(v8::Local<v8::Value> value, const std::string& cancellable_request) {
    if (value->IsPromise()) {
      auto promise = value.As<v8::Promise>();
      const auto started = std::chrono::steady_clock::now();
      bool cancellation_delivered = false;
      while (promise->State() == v8::Promise::kPending) {
        if (!cancellable_request.empty() && !cancellation_delivered && IsCancelled(cancellable_request)) {
          Call("__mgreadCancelJson", {cancellable_request}, 0);
          cancellation_delivered = true;
        }
        uv_run(setup_->event_loop(), UV_RUN_NOWAIT);
        platform_->DrainTasks(isolate_);
        isolate_->PerformMicrotaskCheckpoint();
        if (std::chrono::steady_clock::now() - started > std::chrono::minutes(2)) {
          throw std::runtime_error("node_promise_timeout");
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      }
      if (promise->State() == v8::Promise::kRejected) {
        std::string message = "node_promise_rejected";
        v8::String::Utf8Value reason(isolate_, promise->Result());
        if (*reason && reason.length() > 0) {
          message += ": ";
          message.append(*reason, reason.length());
        }
        throw std::runtime_error(message);
      }
      value = promise->Result();
    }
    v8::String::Utf8Value text(isolate_, value);
    return *text ? std::string(*text, text.length()) : std::string();
  }

  bool IsCancelled(const std::string& request_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    return cancellation_ids_.contains(request_id);
  }

  v8::Local<v8::String> ToV8(const std::string& value) {
    return v8::String::NewFromUtf8(isolate_, value.c_str(), v8::NewStringType::kNormal, value.size()).ToLocalChecked();
  }

  static std::string Quote(const std::string& value) {
    std::string result = "\"";
    for (const char character : value) {
      if (character == '\\' || character == '"') result += '\\';
      result += character;
    }
    return result + "\"";
  }

  static std::string JsonEscape(const std::string& value) {
    std::string result;
    result.reserve(value.size() + 8);
    for (const unsigned char character : value) {
      if (character == '\\' || character == '"') result += '\\';
      if (character == '\n') { result += "\\n"; continue; }
      if (character == '\r') { result += "\\r"; continue; }
      if (character == '\t') { result += "\\t"; continue; }
      result += static_cast<char>(character);
    }
    return result;
  }

  static std::string FileUrl(const std::string& path) {
    std::string url = "file://";
    for (const char character : path) url += character == '\\' ? '/' : character;
    return url;
  }

  void InstallProgressCallback() {
    auto callback = v8::FunctionTemplate::New(isolate_, &NodeHost::ProgressFromNode,
      v8::External::New(isolate_, this))->GetFunction(setup_->context()).ToLocalChecked();
    setup_->context()->Global()->Set(setup_->context(), ToV8("__mgreadReportProgress"), callback).Check();
  }

  static void ProgressFromNode(const v8::FunctionCallbackInfo<v8::Value>& info) {
    auto* host = static_cast<NodeHost*>(v8::Local<v8::External>::Cast(info.Data())->Value());
    if (info.Length() == 0) return;
    v8::String::Utf8Value value(info.GetIsolate(), info[0]);
    if (*value) host->ReportProgress(std::string(*value, value.length()));
  }

  static void ProgressOnJs(napi_env env, napi_value callback, void*, void* data) {
    auto* payload = static_cast<std::string*>(data);
    napi_value argument = StringValue(env, *payload);
    napi_call_function(env, nullptr, callback, 1, &argument, nullptr);
    delete payload;
  }

  void Stop() {
    if (setup_ && env_ && isolate_) {
      v8::Locker locker(isolate_);
      v8::Isolate::Scope isolate_scope(isolate_);
      v8::HandleScope handle_scope(isolate_);
      v8::Context::Scope context_scope(setup_->context());
      env_ = nullptr;
      setup_.reset();
    }
    if (platform_) {
      cppgc::ShutdownProcess();
      v8::V8::Dispose();
      v8::V8::DisposePlatform();
      platform_.reset();
    }
    if (initialization_) {
      node::TearDownOncePerProcess();
      initialization_.reset();
    }
    initialized_ = false;
  }

  std::mutex mutex_;
  std::condition_variable condition_;
  std::deque<std::function<void()>> queue_;
  std::thread thread_;
  bool disposed_ = false;
  bool initialized_ = false;
  std::exception_ptr initialization_error_;
  std::set<std::string> cancellation_ids_;
  std::string runtime_root_;
  std::string data_root_;
  std::string inbox_root_;
  std::shared_ptr<node::InitializationResult> initialization_;
  std::unique_ptr<node::MultiIsolatePlatform> platform_;
  std::unique_ptr<node::CommonEnvironmentSetup> setup_;
  v8::Isolate* isolate_ = nullptr;
  node::Environment* env_ = nullptr;
  std::mutex callback_mutex_;
  napi_ref progress_function_ = nullptr;
  napi_threadsafe_function progress_function_tsfn_ = nullptr;
};

NodeHost& Host() {
  static NodeHost host;
  return host;
}

napi_value Initialize(napi_env env, napi_callback_info info) {
  size_t argc = 3; napi_value argv[3];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 3) { napi_throw_error(env, "invalid_arguments", "initialize expects three paths"); return nullptr; }
  try { Host().Initialize(Utf8(env, argv[0]), Utf8(env, argv[1]), Utf8(env, argv[2])); }
  catch (const std::exception& error) { napi_throw_error(env, "runtime_start_failed", error.what()); return nullptr; }
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value Invoke(napi_env env, napi_callback_info info) {
  size_t argc = 4; napi_value argv[4];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 4) { napi_throw_error(env, "invalid_arguments", "invoke expects four arguments"); return nullptr; }
  double deadline = 0; napi_get_value_double(env, argv[3], &deadline);
  try {
    return StringValue(env, Host().Invoke(Utf8(env, argv[0]), Utf8(env, argv[1]), Utf8(env, argv[2]), deadline));
  } catch (const std::exception& error) { napi_throw_error(env, "runtime_invocation_failed", error.what()); return nullptr; }
}

napi_value Cancel(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1]; napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  napi_value result; napi_get_boolean(env, argc == 1 && Host().Cancel(Utf8(env, argv[0])), &result); return result;
}

napi_value RuntimePaths(napi_env env, napi_callback_info) {
  return StringValue(env, Host().RuntimePaths());
}

napi_value MaterializeTransfer(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value argv[2];
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 2) { napi_throw_error(env, "invalid_arguments", "materializeTransfer expects two paths"); return nullptr; }
  try {
    return StringValue(env, Host().MaterializeTransfer(Utf8(env, argv[0]), Utf8(env, argv[1])));
  } catch (const std::exception& error) { napi_throw_error(env, "runtime_transfer_failed", error.what()); return nullptr; }
}

napi_value Restart(napi_env env, napi_callback_info) {
  try { return StringValue(env, Host().Restart()); }
  catch (const std::exception& error) { napi_throw_error(env, "runtime_restart_failed", error.what()); return nullptr; }
}

napi_value SetProgress(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1]; napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc != 1) { napi_throw_error(env, "invalid_arguments", "setProgressCallback expects a function"); return nullptr; }
  Host().SetProgress(env, argv[0]); napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value Dispose(napi_env env, napi_callback_info) {
  Host().Dispose();
  Host().ClearProgress(env);
  napi_value result; napi_get_undefined(env, &result); return result;
}

napi_value RuntimeVersion(napi_env env, napi_callback_info) { return StringValue(env, kNodeVersion); }
napi_value NativeNodeHostAvailable(napi_env env, napi_callback_info) {
  napi_value result;
  napi_get_boolean(env, true, &result);
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
    {"initialize", nullptr, Initialize, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"invoke", nullptr, Invoke, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"cancelInvocation", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"runtimePaths", nullptr, RuntimePaths, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"materializeTransfer", nullptr, MaterializeTransfer, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"restart", nullptr, Restart, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setProgressCallback", nullptr, SetProgress, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"dispose", nullptr, Dispose, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"runtimeVersion", nullptr, RuntimeVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"nativeNodeHostAvailable", nullptr, NativeNodeHostAvailable, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
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

extern "C" __attribute__((constructor)) void RegisterMgReadNodeHost() { napi_module_register(&g_module); }
