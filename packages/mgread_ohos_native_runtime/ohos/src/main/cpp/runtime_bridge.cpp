#include "runtime_bridge.h"

RuntimeBridge::RuntimeBridge(const std::string& config) {
  handle_ = mgread_runtime_create(config.c_str());
}

RuntimeBridge::~RuntimeBridge() {
  std::lock_guard<std::mutex> lock(mutex_);
  mgread_runtime_free(handle_);
  handle_ = nullptr;
}

int RuntimeBridge::Start() {
  std::lock_guard<std::mutex> lock(mutex_);
  return mgread_runtime_start(handle_);
}

int RuntimeBridge::Invoke(const std::string& request, std::string* response) {
  if (response == nullptr) return MGREAD_RUNTIME_INVALID_ARGUMENT;
  char* raw = nullptr;
  const int code = mgread_runtime_invoke(handle_, request.c_str(), &raw);
  if (code == MGREAD_RUNTIME_OK && raw != nullptr) *response = raw;
  mgread_runtime_free_string(raw);
  return code;
}

std::string RuntimeBridge::LastError() {
  char* raw = nullptr;
  const int code = mgread_runtime_last_error(&raw);
  std::string response = raw == nullptr ? std::string() : std::string(raw);
  mgread_runtime_free_string(raw);
  return code == MGREAD_RUNTIME_OK ? response : std::string();
}

int RuntimeBridge::Cancel(const std::string& request_id) {
  return mgread_runtime_cancel(handle_, request_id.c_str());
}

int RuntimeBridge::Stop() {
  std::lock_guard<std::mutex> lock(mutex_);
  return mgread_runtime_stop(handle_);
}

int RuntimeBridge::Restart() {
  std::lock_guard<std::mutex> lock(mutex_);
  return mgread_runtime_restart(handle_);
}
