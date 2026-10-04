#!/usr/bin/env bash

# Build the exact Node Runtime used by the OHOS host.
#
# Ownership: this script owns only the reproducible Node.js OHOS shared build
# inputs and output. It does not stage a Flutter asset or change capability
# flags; the shared library must pass the native host and device probes first.
# The build must run on a native Linux x64 host with a Linux OHOS SDK/LLVM
# toolchain. The Windows DevEco installation is suitable for HAP builds, but
# is not a substitute for the Linux host tools required by Node's GYP build.

set -euo pipefail

node_version="${1:-v26.10.0}"
work_root="${2:-${PWD}/.ohos-node-build}"
target_cpu="${3:-arm64}"
ohos_sdk_root="${OHOS_SDK_ROOT:-}"
ohos_llvm_root="${OHOS_LLVM_ROOT:-}"
ohos_cxx_frontend="${OHOS_CXX_FRONTEND:-}"
ohos_libcxx_include_root=""
host_cc="${CC_host:-cc}"
host_cxx="${CXX_host:-c++}"
jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This build must run on a native Linux x64 host." >&2
  exit 2
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "This build requires an x86_64 host for the Node GYP host tools." >&2
  exit 2
fi
if [[ "$node_version" != "v26.10.0" ]]; then
  echo "MgRead OHOS requires Node v26.10.0; refusing $node_version." >&2
  exit 2
fi
if [[ "$target_cpu" != "arm64" && "$target_cpu" != "x64" ]]; then
  echo "The OpenHarmony target must be arm64 or x64, got ${target_cpu}." >&2
  exit 2
fi
if [[ -z "$ohos_sdk_root" || -z "$ohos_llvm_root" ]]; then
  echo "Set OHOS_SDK_ROOT and OHOS_LLVM_ROOT to the Linux OHOS SDK and LLVM roots." >&2
  exit 2
fi
if [[ ! -d "$ohos_sdk_root" || ! -d "$ohos_llvm_root" ]]; then
  echo "OHOS_SDK_ROOT and OHOS_LLVM_ROOT must point to existing directories." >&2
  exit 2
fi
ohos_libcxx_include_root="${ohos_llvm_root}/include/libcxx-ohos/include/c++/v1"
if [[ ! -d "$ohos_libcxx_include_root" ]]; then
  echo "OpenHarmony libc++ headers not found: ${ohos_libcxx_include_root}" >&2
  exit 2
fi

source_url="https://nodejs.org/dist/${node_version}/node-${node_version}.tar.gz"
source_sums_url="https://nodejs.org/dist/${node_version}/SHASUMS256.txt"
source_archive="${work_root}/node-${node_version}.tar.gz"
source_sums="${work_root}/SHASUMS256.txt"
source_archive_root="${work_root}/node-${node_version}"
source_root="${work_root}/node-${node_version}-openharmony-${target_cpu}-source"
install_root="${work_root}/node-${node_version}-openharmony-${target_cpu}"
target_triple="aarch64-unknown-linux-ohos"
target_clang="aarch64-unknown-linux-ohos-clang"
target_clangxx="aarch64-unknown-linux-ohos-clang++"
if [[ "$target_cpu" == "x64" ]]; then
  target_triple="x86_64-unknown-linux-ohos"
  target_clang="x86_64-unknown-linux-ohos-clang"
  target_clangxx="x86_64-unknown-linux-ohos-clang++"
fi
script_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compat_include_root="${work_root}/mgread-ohos-compat"

mkdir -p "$work_root"
if [[ ! -f "$source_archive" ]]; then
  curl --fail --location --show-error --silent --output "$source_archive" "$source_url"
fi
curl --fail --location --show-error --silent --output "$source_sums" "$source_sums_url"
(cd "$work_root" && grep " node-${node_version}\.tar\.gz$" "$source_sums" | sha256sum --check --status -)

# Node's generated Makefiles do not quote CC/CXX values. DevEco is commonly
# installed under a Windows path containing spaces, so expose the OHOS clang
# drivers through temporary no-space wrappers before configure records them.
toolchain_wrapper_root="${work_root}/.toolchain-wrappers"
rm -rf -- "$toolchain_wrapper_root"
mkdir -p "$toolchain_wrapper_root"
make_toolchain_wrapper() {
  local wrapper_name="$1"
  local compiler_path="$2"
  printf '%s\n' '#!/usr/bin/env bash' "exec \"${compiler_path}\" \"\$@\"" \
    > "${toolchain_wrapper_root}/${wrapper_name}"
  chmod +x "${toolchain_wrapper_root}/${wrapper_name}"
}
make_cxx_frontend_wrapper() {
  local wrapper_name="$1"
  local frontend_path="$2"
  local linker_path="$3"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'compile=0' \
    'for arg in "$@"; do' \
    '  if [[ "$arg" == "-c" || "$arg" == "-S" || "$arg" == "-E" ]]; then' \
    '    compile=1' \
    '  fi' \
    'done' \
    "if [[ \"\$compile\" == 1 ]]; then exec \"${frontend_path}\" --target=${target_triple} --sysroot=\"${ohos_sdk_root}/native/sysroot\" -stdlib=libc++ -nostdinc++ -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE -isystem \"${compat_include_root}\" -isystem /usr/include/c++/v1 \"\$@\"; fi" \
    "exec \"${linker_path}\" \"\$@\"" \
    > "${toolchain_wrapper_root}/${wrapper_name}"
  chmod +x "${toolchain_wrapper_root}/${wrapper_name}"
}

clang_path="${ohos_llvm_root}/bin/${target_clang}"
cxx_path="${ohos_llvm_root}/bin/${target_clangxx}"
if [[ "$ohos_llvm_root" == *" "* ]]; then
  make_toolchain_wrapper "$target_clang" "$clang_path"
  make_toolchain_wrapper "$target_clangxx" "$cxx_path"
  clang_path="${toolchain_wrapper_root}/${target_clang}"
  cxx_path="${toolchain_wrapper_root}/${target_clangxx}"
fi
if [[ -n "$ohos_cxx_frontend" ]]; then
  if [[ ! -x "$ohos_cxx_frontend" ]]; then
    echo "OHOS_CXX_FRONTEND must point to an executable Clang++ frontend." >&2
    exit 2
  fi
  make_cxx_frontend_wrapper "$target_clangxx" \
    "$ohos_cxx_frontend" \
    "${ohos_llvm_root}/bin/${target_clangxx}"
  cxx_path="${toolchain_wrapper_root}/${target_clangxx}"
fi

if [[ ! -f "${source_archive_root}/configure.py" ]]; then
  tar --extract --gzip --file "$source_archive" --directory "$work_root"
fi
if [[ ! -f "${source_root}/configure.py" ]]; then
  cp --archive "$source_archive_root" "$source_root"
fi
if [[ ! -f "${source_root}/configure.py" ]]; then
  echo "Node source tree was not materialized for ${target_cpu}: ${source_root}" >&2
  exit 1
fi

mkdir -p "$install_root"
mkdir -p "$compat_include_root"
# Use the newer bundled libc++ headers for Node 26's ranges surface, while
# matching the OHOS runtime's ABI inline namespace. The SDK's older headers
# are still validated above and remain the source of the target sysroot.
cp /usr/include/c++/v1/__config_site "${compat_include_root}/__config_site"
sed -i 's/__1/__n1/g' "${compat_include_root}/__config_site"
for compat_header in source_location ohos-cxx-compat.h; do
  if [[ ! -f "${compat_include_root}/${compat_header}" ]] ||
    ! cmp -s "${script_root}/ohos-compat/${compat_header}" "${compat_include_root}/${compat_header}"; then
    cp "${script_root}/ohos-compat/${compat_header}" "${compat_include_root}/${compat_header}"
  fi
done
mkdir -p "${compat_include_root}/__support/musl"
cp "${script_root}/ohos-compat/__support/musl/xlocale.h" \
  "${compat_include_root}/__support/musl/xlocale.h"

# Node 26.10.0's bundled ada header has a comparator that mutates local
# decoding state but omits the reference capture required by Clang. Keep this
# narrow source fix in the reproducible OHOS build instead of carrying a fork
# of the vendored dependency in the repository.
ada_header="${source_root}/deps/ada/ada.h"
if [[ -f "$ada_header" ]]; then
  if ! grep -Fq 'std::ranges::stable_sort(params, [&](const key_value_pair' "$ada_header"; then
    sed -i 's/std::ranges::stable_sort(params, \[\](const key_value_pair/std::ranges::stable_sort(params, [\&](const key_value_pair/' "$ada_header"
  fi
  if ! grep -Fq 'std::ranges::stable_sort(params, [&](const key_value_pair' "$ada_header"; then
    echo "Failed to apply the Clang compatibility fix to ${ada_header}." >&2
    exit 1
  fi
fi

# The OHOS SDK libc++ shipped with the supported DevEco toolchain does not
# provide Node 26's ranges view aliases. Keep the compatibility change local to
# this generated Node source tree: builtin ids are only consumed as an
# iterable and then converted to a JavaScript array, so a vector is equivalent
# here and avoids carrying a second ranges implementation.
builtins_header="${source_root}/src/node_builtins.h"
builtins_source="${source_root}/src/node_builtins.cc"
util_header="${source_root}/src/util.h"
util_inline="${source_root}/src/util-inl.h"
if grep -Fq 'std::ranges::keys_view' "$builtins_header"; then
  perl -0pi -e \
    's/\[\[nodiscard\]\] std::ranges::keys_view<\n\s*std::ranges::ref_view<const BuiltinSourceMap>>\n\s*GetBuiltinIds\(\) const;/[[nodiscard]] std::vector<std::string> GetBuiltinIds() const;/s' \
    "$builtins_header"
  perl -0pi -e \
    's/std::ranges::keys_view<std::ranges::ref_view<const BuiltinSourceMap>>\nBuiltinLoader::GetBuiltinIds\(\) const \{\n  return std::views::keys\(\*source_\.read\(\)\);\n\}/std::vector<std::string> BuiltinLoader::GetBuiltinIds() const {\n  std::vector<std::string> ids;\n  const auto\& sources = *source_.read();\n  ids.reserve(sources.size());\n  for (const auto\& entry : sources) ids.push_back(entry.first);\n  return ids;\n}/s' \
    "$builtins_source"
fi
sed -i 's/std::ranges::elements_view<T, U>/std::vector<T>/g' \
  "$util_header" "$util_inline"

export PATH="${ohos_llvm_root}/bin:${PATH}"
export CC="${clang_path} -fno-emulated-tls"
export CXX="${cxx_path} -fno-emulated-tls"
export CC_host="$host_cc"
export CXX_host="$host_cxx"
export CXXFLAGS="${CXXFLAGS:-} -I${compat_include_root} -include ${compat_include_root}/ohos-cxx-compat.h"

pushd "$source_root" >/dev/null
if [[ ! -f out/Makefile ]]; then
  configure_args=(
    "--dest-cpu=${target_cpu}"
    --dest-os=openharmony
    --cross-compiling
    --shared
    --openssl-no-asm
    "--prefix=${install_root}"
  )
  if [[ "$target_cpu" == "arm64" ]]; then
    configure_args+=(--with-arm-fpu=vfp)
  fi
  python3 ./configure "${configure_args[@]}"
else
  echo "Reusing existing OpenHarmony Node configure output at ${source_root}/out."
fi
# The default Node target also builds node_mksnapshot and cctest.  During an
# OpenHarmony cross build node_mksnapshot is emitted with the target toolset,
# even though it is a host-only helper; the shared runtime uses
# node_snapshot_stub and does not need that helper.  Build only the artifact
# this package stages.
if [[ -f "${install_root}/lib/libnode.so.147" ]]; then
  echo "Reusing existing staged OpenHarmony Node runtime at ${install_root}."
else
  make -C out -j"$jobs" libnode

  # `make install` depends on Node's default `all` target, which also tries to
  # link the target-toolset node_mksnapshot helper.  Stage the shared library
  # and public headers directly because this package only consumes those files.
  rm -rf -- "$install_root"
  mkdir -p "$install_root/lib" "$install_root/include/node"
  cp out/Release/libnode.so.* "$install_root/lib/"
  find src -maxdepth 1 -type f -name '*.h' -exec cp {} "$install_root/include/node/" \;
fi
popd >/dev/null

shared_library="$(find "$install_root" -type f \( -name 'libnode.so' -o -name 'libnode.so.*' \) -print -quit)"
if [[ -z "$shared_library" ]]; then
  echo "Node shared library was not produced; refusing to stage an executable-only build." >&2
  exit 1
fi
if [[ "$shared_library" != "${install_root}/lib/libnode.so" ]]; then
  cp --force "$shared_library" "${install_root}/lib/libnode.so"
fi

source_commit="$(git -C "$source_root" rev-parse HEAD 2>/dev/null || echo "source-archive-${node_version}")"
printf '{\n  "nodeVersion": "26.10.0",\n  "target": "openharmony-%s",\n  "sourceCommit": "%s",\n  "sharedLibrary": "%s"\n}\n' \
  "$target_cpu" \
  "$source_commit" \
  "${shared_library#"$install_root/"}" \
  > "${install_root}/mgread-node-build.json"

echo "Built verified Node 26.10.0 OpenHarmony ${target_cpu} shared runtime at ${install_root}."
