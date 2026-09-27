#ifndef MGREAD_RUNTIME_H
#define MGREAD_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mgread_runtime_handle mgread_runtime_handle;

enum mgread_runtime_error {
  MGREAD_RUNTIME_OK = 0,
  MGREAD_RUNTIME_INVALID_ARGUMENT = 1,
  MGREAD_RUNTIME_NOT_INITIALIZED = 2,
  MGREAD_RUNTIME_TIMEOUT = 3,
  MGREAD_RUNTIME_CANCELLED = 4,
  MGREAD_RUNTIME_NETWORK_ERROR = 5,
  MGREAD_RUNTIME_PLUGIN_ERROR = 6,
  MGREAD_RUNTIME_RESOURCE_ERROR = 7,
  MGREAD_RUNTIME_CRASHED = 8,
  MGREAD_RUNTIME_UNSUPPORTED = 9,
};

const char* mgread_runtime_version(void);
mgread_runtime_handle* mgread_runtime_create(const char* config_json);
int32_t mgread_runtime_start(mgread_runtime_handle* runtime);
int32_t mgread_runtime_invoke(mgread_runtime_handle* runtime, const char* request_json, char** response_json);
int32_t mgread_runtime_cancel(mgread_runtime_handle* runtime, const char* request_id);
int32_t mgread_runtime_stop(mgread_runtime_handle* runtime);
int32_t mgread_runtime_restart(mgread_runtime_handle* runtime);
void mgread_runtime_free_string(char* value);
void mgread_runtime_free(mgread_runtime_handle* runtime);

#ifdef __cplusplus
}
#endif

#endif
