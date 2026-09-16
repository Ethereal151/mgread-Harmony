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

node_version="${1:-v24.16.0}"
work_root="${2:-${PWD}/.ohos-node-build}"
ohos_sdk_root="${OHOS_SDK_ROOT:-}"
ohos_llvm_root="${OHOS_LLVM_ROOT:-}"
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
if [[ "$node_version" != "v24.16.0" ]]; then
  echo "MgRead requires Node v24.16.0; refusing $node_version." >&2
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

mkdir -p "$work_root"
if [[ ! -f "$source_archive" ]]; then
  curl --fail --location --show-error --silent --output "$source_archive" "$source_url"
fi
curl --fail --location --show-error --silent --output "$source_sums" "$source_sums_url"
(cd "$work_root" && grep " node-${node_version}\.tar\.gz$" "$source_sums" | sha256sum --check --status -)

if [[ ! -f "${source_root}/configure.py" ]]; then
  tar --extract --gzip --file "$source_archive" --directory "$work_root"
fi

rm -rf "$install_root"
mkdir -p "$install_root"

export PATH="${ohos_llvm_root}/bin:${PATH}"
export CC="${ohos_llvm_root}/bin/aarch64-unknown-linux-ohos-clang -fno-emulated-tls"
export CXX="${ohos_llvm_root}/bin/aarch64-unknown-linux-ohos-clang++ -fno-emulated-tls"
export CC_host="$host_cc"
export CXX_host="$host_cxx"

pushd "$source_root" >/dev/null
python3 ./configure \
  --dest-cpu=arm64 \
  --dest-os=openharmony \
  --cross-compiling \
  --shared \
  --enable-static \
  --openssl-no-asm \
  --prefix="$install_root"
make -j"$jobs"
make install
popd >/dev/null

shared_library="$(find "$install_root" -type f \( -name 'libnode.so' -o -name 'libnode.so.*' \) -print -quit)"
if [[ -z "$shared_library" ]]; then
  echo "Node shared library was not produced; refusing to stage an executable-only build." >&2
  exit 1
fi

source_commit="$(git -C "$source_root" rev-parse HEAD 2>/dev/null || echo "source-archive-${node_version}")"
printf '{\n  "nodeVersion": "24.16.0",\n  "target": "openharmony-arm64",\n  "sourceCommit": "%s",\n  "sharedLibrary": "%s"\n}\n' \
  "$source_commit" \
  "${shared_library#"$install_root/"}" \
  > "${install_root}/mgread-node-build.json"

echo "Built verified Node 24.16.0 OpenHarmony arm64 shared runtime at ${install_root}."
