#!/usr/bin/env bash

# Build the exact Node Runtime used by the OHOS host.
#
# Ownership: this script owns only the reproducible Node.js OHOS arm64 build
# inputs and output. It does not stage a Flutter asset or change capability
# flags; the shared library must pass the native host and device probes first.
# The build must run on a native Linux x64 host with a Linux OHOS SDK/LLVM
# toolchain. The Windows DevEco installation is suitable for HAP builds, but
# is not a substitute for the Linux host tools required by Node's GYP build.

set -euo pipefail

node_version="${1:-v26.10.0}"
work_root="${2:-${PWD}/.ohos-node-build}"
ohos_sdk_root="${OHOS_SDK_ROOT:-}"
ohos_llvm_root="${OHOS_LLVM_ROOT:-}"
ohos_cxx_frontend="${OHOS_CXX_FRONTEND:-}"
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
if [[ -z "$ohos_sdk_root" || -z "$ohos_llvm_root" ]]; then
  echo "Set OHOS_SDK_ROOT and OHOS_LLVM_ROOT to the Linux OHOS SDK and LLVM roots." >&2
  exit 2
fi
if [[ ! -d "$ohos_sdk_root" || ! -d "$ohos_llvm_root" ]]; then
  echo "OHOS_SDK_ROOT and OHOS_LLVM_ROOT must point to existing directories." >&2
  exit 2
fi

source_url="https://nodejs.org/dist/${node_version}/node-${node_version}.tar.gz"
source_sums_url="https://nodejs.org/dist/${node_version}/SHASUMS256.txt"
source_archive="${work_root}/node-${node_version}.tar.gz"
source_sums="${work_root}/SHASUMS256.txt"
source_root="${work_root}/node-${node_version}"
install_root="${work_root}/node-${node_version}-openharmony-arm64"
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
    "if [[ \"\$compile\" == 1 ]]; then exec \"${frontend_path}\" --target=aarch64-unknown-linux-ohos --sysroot=\"${ohos_sdk_root}/native/sysroot\" -stdlib=libc++ -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE -isystem /usr/include/c++/v1 \"\$@\"; fi" \
    "exec \"${linker_path}\" \"\$@\"" \
    > "${toolchain_wrapper_root}/${wrapper_name}"
  chmod +x "${toolchain_wrapper_root}/${wrapper_name}"
}

clang_path="${ohos_llvm_root}/bin/aarch64-unknown-linux-ohos-clang"
cxx_path="${ohos_llvm_root}/bin/aarch64-unknown-linux-ohos-clang++"
if [[ "$ohos_llvm_root" == *" "* ]]; then
  make_toolchain_wrapper aarch64-unknown-linux-ohos-clang "$clang_path"
  make_toolchain_wrapper aarch64-unknown-linux-ohos-clang++ "$cxx_path"
  clang_path="${toolchain_wrapper_root}/aarch64-unknown-linux-ohos-clang"
  cxx_path="${toolchain_wrapper_root}/aarch64-unknown-linux-ohos-clang++"
fi
if [[ -n "$ohos_cxx_frontend" ]]; then
  if [[ ! -x "$ohos_cxx_frontend" ]]; then
    echo "OHOS_CXX_FRONTEND must point to an executable Clang++ frontend." >&2
    exit 2
  fi
  make_cxx_frontend_wrapper aarch64-unknown-linux-ohos-clang++ \
    "$ohos_cxx_frontend" \
    "${ohos_llvm_root}/bin/aarch64-unknown-linux-ohos-clang++"
  cxx_path="${toolchain_wrapper_root}/aarch64-unknown-linux-ohos-clang++"
fi

if [[ ! -f "${source_root}/configure.py" ]]; then
  tar --extract --gzip --file "$source_archive" --directory "$work_root"
fi

mkdir -p "$install_root"
mkdir -p "$compat_include_root"
for compat_header in source_location ohos-cxx-compat.h; do
  if [[ ! -f "${compat_include_root}/${compat_header}" ]] ||
    ! cmp -s "${script_root}/ohos-compat/${compat_header}" "${compat_include_root}/${compat_header}"; then
    cp "${script_root}/ohos-compat/${compat_header}" "${compat_include_root}/${compat_header}"
  fi
done

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

export PATH="${ohos_llvm_root}/bin:${PATH}"
export CC="${clang_path} -fno-emulated-tls"
export CXX="${cxx_path} -fno-emulated-tls"
export CC_host="$host_cc"
export CXX_host="$host_cxx"
export CXXFLAGS="${CXXFLAGS:-} -I${compat_include_root} -include ${compat_include_root}/ohos-cxx-compat.h"

pushd "$source_root" >/dev/null
if [[ ! -f out/Makefile ]]; then
  python3 ./configure \
    --dest-cpu=arm64 \
    --dest-os=openharmony \
    --cross-compiling \
    --shared \
    --with-arm-fpu=vfp \
    --openssl-no-asm \
    --prefix="$install_root"
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

source_commit="$(git -C "$source_root" rev-parse HEAD 2>/dev/null || echo "source-archive-${node_version}")"
printf '{\n  "nodeVersion": "26.10.0",\n  "target": "openharmony-arm64",\n  "sourceCommit": "%s",\n  "sharedLibrary": "%s"\n}\n' \
  "$source_commit" \
  "${shared_library#"$install_root/"}" \
  > "${install_root}/mgread-node-build.json"

echo "Built verified Node 26.10.0 OpenHarmony arm64 shared runtime at ${install_root}."
