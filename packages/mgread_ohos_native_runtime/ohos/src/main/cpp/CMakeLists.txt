cmake_minimum_required(VERSION 3.16)
project(mgread_ohos_native_runtime)

find_path(OHOS_NAPI_INCLUDE napi/native_api.h
  PATHS "$ENV{OHOS_SDK_ROOT}/native/sysroot/usr/include"
        "$ENV{DEVECO_SDK_HOME}/native/sysroot/usr/include"
  NO_DEFAULT_PATH)
if(NOT OHOS_NAPI_INCLUDE)
  message(FATAL_ERROR "Could not locate OpenHarmony napi/native_api.h")
endif()

set(MGREAD_RUST_RUNTIME_LIB "$ENV{MGREAD_RUST_RUNTIME_LIB}" CACHE FILEPATH "Rust OHOS runtime library")
set(MGREAD_RUST_RUNTIME_INCLUDE "$ENV{MGREAD_RUST_RUNTIME_INCLUDE}" CACHE PATH "Rust runtime C header directory")
if(OHOS_ARCH STREQUAL "x86_64" OR NOT MGREAD_RUST_RUNTIME_LIB OR NOT EXISTS "${MGREAD_RUST_RUNTIME_LIB}" OR NOT MGREAD_RUST_RUNTIME_INCLUDE OR NOT EXISTS "${MGREAD_RUST_RUNTIME_INCLUDE}/mgread_runtime.h")
  # Keep ordinary builds loadable while returning an explicit unsupported
  # result until an architecture-specific Rust artifact is supplied.
  add_library(mgread_ohos_native_runtime SHARED napi_module_x86_stub.cpp)
  target_include_directories(mgread_ohos_native_runtime PRIVATE "${OHOS_NAPI_INCLUDE}")
  target_link_libraries(mgread_ohos_native_runtime PRIVATE ace_napi.z)
else()
  add_library(mgread_ohos_native_runtime SHARED napi_module.cpp runtime_bridge.cpp)
  target_include_directories(mgread_ohos_native_runtime PRIVATE "${OHOS_NAPI_INCLUDE}" "${MGREAD_RUST_RUNTIME_INCLUDE}")
  target_link_libraries(mgread_ohos_native_runtime PRIVATE "${MGREAD_RUST_RUNTIME_LIB}" ace_napi.z)
endif()
target_compile_features(mgread_ohos_native_runtime PRIVATE cxx_std_17)
target_compile_options(mgread_ohos_native_runtime PRIVATE -fvisibility=hidden)
set_target_properties(mgread_ohos_native_runtime PROPERTIES
  OUTPUT_NAME "mgread_ohos_native_runtime"
  BUILD_WITH_INSTALL_RPATH TRUE
  BUILD_RPATH "$ORIGIN"
  INSTALL_RPATH "$ORIGIN")
if(TARGET mgread_ohos_native_runtime AND NOT OHOS_ARCH STREQUAL "x86_64" AND MGREAD_RUST_RUNTIME_LIB AND EXISTS "${MGREAD_RUST_RUNTIME_LIB}" AND MGREAD_RUST_RUNTIME_INCLUDE AND EXISTS "${MGREAD_RUST_RUNTIME_INCLUDE}/mgread_runtime.h")
  add_custom_command(TARGET mgread_ohos_native_runtime POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${MGREAD_RUST_RUNTIME_LIB}"
      "$<TARGET_FILE_DIR:mgread_ohos_native_runtime>/libmgread_rust_runtime.so")
endif()
