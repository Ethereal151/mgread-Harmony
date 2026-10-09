#pragma once

#include <mutex>
#include <string>

#include "mgread_runtime.h"

class RuntimeBridge final {
 public:
  explicit RuntimeBridge(const std::string& config);
  ~RuntimeBridge();
  RuntimeBridge(const RuntimeBridge&) = delete;
  RuntimeBridge& operator=(const RuntimeBridge&) = delete;

  int Start();
  int Invoke(const std::string& request, std::string* response);
  std::string LastError();
  int Cancel(const std::string& request_id);
  int Stop();
  int Restart();

 private:
  std::mutex mutex_;
  mgread_runtime_handle* handle_ = nullptr;
};

class NativeHostBridge final {
 public:
  NativeHostBridge();
  ~NativeHostBridge();
  NativeHostBridge(const NativeHostBridge&) = delete;
  NativeHostBridge& operator=(const NativeHostBridge&) = delete;

  int Start(const std::string& root, const std::string& token,
            const std::string& native_library_dir, bool test_mode,
            std::string* ready);
  int Stop();

 private:
  std::mutex mutex_;
  mgread_native_host_handle* handle_ = nullptr;
};
