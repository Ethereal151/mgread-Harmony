cmake_minimum_required(VERSION 3.16)
project(mgread_node_host)

# MGREAD_NODE_ROOT is the staged Node v26.10.0 OpenHarmony install for the
# selected HAP ABI. Each architecture is validated before linking to prevent
# silently packaging a host built for the other ABI.
set(MGREAD_NODE_ROOT "$ENV{MGREAD_NODE_ROOT}" CACHE PATH "Node OpenHarmony install root" FORCE)
if(NOT MGREAD_NODE_ROOT)
  set(MGREAD_NODE_ROOT "${CMAKE_CURRENT_LIST_DIR}/node-runtime")
  if(OHOS_ARCH STREQUAL "x86_64")
    set(MGREAD_NODE_ROOT "${MGREAD_NODE_ROOT}/x64" CACHE PATH "Node OpenHarmony install root" FORCE)
  else()
    set(MGREAD_NODE_ROOT "${MGREAD_NODE_ROOT}/arm64" CACHE PATH "Node OpenHarmony install root" FORCE)
  endif()
endif()
set(MGREAD_NODE_SOURCE_ROOT "$ENV{MGREAD_NODE_SOURCE_ROOT}" CACHE PATH "Node source root used for public embedding headers" FORCE)
if(NOT MGREAD_NODE_SOURCE_ROOT)
  set(MGREAD_NODE_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/node-source")
endif()
find_path(OHOS_NAPI_INCLUDE napi/native_api.h
  PATHS
    "$ENV{OHOS_SDK_ROOT}/native/sysroot/usr/include"
    "$ENV{HOS_SDK_HOME}/native/sysroot/usr/include"
    "$ENV{OHOS_SDK_HOME}/native/sysroot/usr/include"
    "$ENV{DEVECO_SDK_HOME}/native/sysroot/usr/include"
    "${CMAKE_SYSROOT}/usr/include"
  NO_DEFAULT_PATH)
if(NOT OHOS_NAPI_INCLUDE)
  message(FATAL_ERROR "Could not locate OpenHarmony napi/native_api.h")
endif()

if(OHOS_ARCH STREQUAL "x86_64")
  set(MGREAD_EXPECTED_NODE_TARGET "x64")
else()
  set(MGREAD_EXPECTED_NODE_TARGET "arm64")
endif()
if(NOT EXISTS "${MGREAD_NODE_SOURCE_ROOT}/src/node.h")
  message(FATAL_ERROR "MGREAD_NODE_SOURCE_ROOT must point at the matching Node v26.10.0 source tree")
endif()
set(MGREAD_NODE_TARGET_FILE "${MGREAD_NODE_ROOT}/mgread-node-target.txt")
if(NOT EXISTS "${MGREAD_NODE_TARGET_FILE}")
  message(FATAL_ERROR "The staged Node runtime is missing mgread-node-target.txt; restage the runtime for this ABI")
endif()
file(READ "${MGREAD_NODE_TARGET_FILE}" MGREAD_STAGED_NODE_TARGET)
string(STRIP "${MGREAD_STAGED_NODE_TARGET}" MGREAD_STAGED_NODE_TARGET)
if(NOT "${MGREAD_STAGED_NODE_TARGET}" STREQUAL "${MGREAD_EXPECTED_NODE_TARGET}")
  message(FATAL_ERROR "Staged Node target '${MGREAD_STAGED_NODE_TARGET}' does not match requested target '${MGREAD_EXPECTED_NODE_TARGET}'")
endif()
set(MGREAD_NODE_SONAME "libnode.so")
set(MGREAD_NODE_SONAME_FILE "${MGREAD_NODE_ROOT}/mgread-node-soname.txt")
if(EXISTS "${MGREAD_NODE_SONAME_FILE}")
  file(READ "${MGREAD_NODE_SONAME_FILE}" MGREAD_NODE_SONAME)
  string(STRIP "${MGREAD_NODE_SONAME}" MGREAD_NODE_SONAME)
endif()
if(NOT MGREAD_NODE_SONAME MATCHES "^libnode\\.so(\\.[0-9]+)*$")
  message(FATAL_ERROR "Staged Node SONAME is invalid: ${MGREAD_NODE_SONAME}")
endif()
if(NOT EXISTS "${MGREAD_NODE_ROOT}/lib/${MGREAD_NODE_SONAME}")
  message(FATAL_ERROR "Staged Node SONAME library is missing: ${MGREAD_NODE_ROOT}/lib/${MGREAD_NODE_SONAME}")
endif()
add_library(mgread_node_host SHARED mgread_node_host.cpp)
target_include_directories(mgread_node_host PRIVATE
  "${MGREAD_NODE_SOURCE_ROOT}"
  "${MGREAD_NODE_SOURCE_ROOT}/src"
  # The Node 26.10.0 source archive keeps the matching V8 public headers
  # under deps/v8/include/include; this must precede the compatibility copy
  # at deps/v8/include or node.h sees the pre-Wrappable API.
  "${MGREAD_NODE_SOURCE_ROOT}/deps/v8/include/include"
  "${MGREAD_NODE_SOURCE_ROOT}/deps/v8/include"
  "${MGREAD_NODE_ROOT}/include/node")
target_link_libraries(mgread_node_host PRIVATE
  "${MGREAD_NODE_ROOT}/lib/${MGREAD_NODE_SONAME}"
  ace_napi.z
  dl
  pthread)
# HarmonyOS packages the build-tree artifact directly, so the artifact must
# resolve the selected Node SONAME next to itself on device.
set_target_properties(mgread_node_host PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN")
add_custom_command(TARGET mgread_node_host POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${MGREAD_NODE_ROOT}/lib/${MGREAD_NODE_SONAME}"
    "$<TARGET_FILE_DIR:mgread_node_host>/${MGREAD_NODE_SONAME}")
target_compile_features(mgread_node_host PRIVATE cxx_std_20)
target_compile_options(mgread_node_host PRIVATE -fvisibility=hidden -fno-rtti)

set_target_properties(mgread_node_host PROPERTIES OUTPUT_NAME "mgread_node_host")
