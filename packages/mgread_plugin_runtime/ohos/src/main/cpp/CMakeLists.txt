cmake_minimum_required(VERSION 3.16)
project(mgread_node_host)

# MGREAD_NODE_ROOT is an extracted Node v24.16.0 OpenHarmony arm64 install
# produced by tools/build-ohos-node.sh. It is deliberately supplied as a
# build input instead of checked into this package.
set(MGREAD_NODE_ROOT "$ENV{MGREAD_NODE_ROOT}" CACHE PATH "Node OpenHarmony install root")
if(NOT MGREAD_NODE_ROOT)
  set(MGREAD_NODE_ROOT "${CMAKE_CURRENT_LIST_DIR}/node-runtime")
endif()
set(MGREAD_NODE_SOURCE_ROOT "$ENV{MGREAD_NODE_SOURCE_ROOT}" CACHE PATH "Node source root used for public embedding headers")
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
  add_library(mgread_node_host SHARED mgread_node_host_x86_stub.cpp)
  target_include_directories(mgread_node_host PRIVATE "${OHOS_NAPI_INCLUDE}")
  target_link_libraries(mgread_node_host PRIVATE ace_napi.z)
else()
  if(NOT EXISTS "${MGREAD_NODE_ROOT}/lib/libnode.so")
    message(FATAL_ERROR "MGREAD_NODE_ROOT must contain lib/libnode.so from the v24.16.0 shared build")
  endif()
  if(NOT EXISTS "${MGREAD_NODE_SOURCE_ROOT}/src/node.h")
    message(FATAL_ERROR "MGREAD_NODE_SOURCE_ROOT must point at the matching Node v24.16.0 source tree")
  endif()
  add_library(mgread_node_host SHARED mgread_node_host.cpp)
  target_include_directories(mgread_node_host PRIVATE
    "${MGREAD_NODE_SOURCE_ROOT}/src"
    "${MGREAD_NODE_SOURCE_ROOT}/deps/v8/include"
    "${MGREAD_NODE_ROOT}/include/node")
  target_link_libraries(mgread_node_host PRIVATE
    "${MGREAD_NODE_ROOT}/lib/libnode.so"
    ace_napi.z
    dl
    pthread)
  # HarmonyOS packages the build-tree artifact directly, so the artifact must
  # resolve libnode.so next to itself on device instead of the host build path.
  set_target_properties(mgread_node_host PROPERTIES
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN")
  add_custom_command(TARGET mgread_node_host POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${MGREAD_NODE_ROOT}/lib/libnode.so"
      "$<TARGET_FILE_DIR:mgread_node_host>/libnode.so")
endif()
target_compile_features(mgread_node_host PRIVATE cxx_std_20)
target_compile_options(mgread_node_host PRIVATE -fvisibility=hidden -fno-rtti)

set_target_properties(mgread_node_host PROPERTIES OUTPUT_NAME "mgread_node_host")
