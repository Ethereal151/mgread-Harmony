# Build and package the Alice source for Windows x64, Android arm64, and OHOS
# arm64. The OHOS artifact uses the OHOS Rust target and linker; it must not be
# replaced with the Android `.so` because the two ELF ABIs are different.
# Rust 1.97.1, Cargo.lock, target triples, and Android 16 KiB page alignment
# are fixed here; packaging emits one portable archive with the selected binaries.
[CmdletBinding()]
param(
  [string]$NdkHome = "$env:LOCALAPPDATA/Android/Sdk/ndk/28.2.13676358",
  [string]$OhosSdkNative = 'D:\DevEco Studio\sdk\default\openharmony\native',
  [string]$Output = (Join-Path $PSScriptRoot '..\dist\aisishuwu-native-0.3.0.mgplugin')
)

$ErrorActionPreference = 'Stop'
$toolchain = '1.97.1'
$windowsTarget = 'x86_64-pc-windows-msvc'
$arm64Target = 'aarch64-linux-android'
$ohosArm64Target = 'aarch64-unknown-linux-ohos'
$rustup = (Get-Command rustup -ErrorAction Stop).Source

$rustcVersion = (& $rustup run $toolchain rustc --version).Trim()
if ($LASTEXITCODE -ne 0 -or $rustcVersion -notmatch '^rustc 1\.97\.1(?:\s|$)') {
  throw "Rust toolchain $toolchain is unavailable or has an unexpected compiler version."
}
$cargoVersion = (& $rustup run $toolchain cargo --version).Trim()
if ($LASTEXITCODE -ne 0 -or $cargoVersion -notmatch '^cargo 1\.97\.1(?:\s|$)') {
  throw "Cargo toolchain $toolchain is unavailable or has an unexpected version."
}

$requiredTargets = @($windowsTarget, $arm64Target, $ohosArm64Target)
$installedTargets = @(& $rustup target list --installed --toolchain $toolchain)
if ($LASTEXITCODE -ne 0) { throw "Could not inspect installed Rust targets for $toolchain." }
$missingTargets = @($requiredTargets | Where-Object { $_ -notin $installedTargets })
if ($missingTargets.Count -gt 0) {
  throw "Rust $toolchain is missing installed targets: $($missingTargets -join ', ')."
}

$ndkBin = Join-Path $NdkHome 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$arm64Clang = Join-Path $ndkBin 'aarch64-linux-android24-clang.cmd'
foreach ($compiler in @($arm64Clang)) {
  if (-not [System.IO.File]::Exists($compiler)) {
    throw "The Android NDK target linker was not found: $compiler"
  }
}

$crateRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$targetRoot = Join-Path $crateRoot 'target'
$windowsDll = Join-Path $targetRoot "$windowsTarget\release\aisishuwu_native.dll"
$arm64So = Join-Path $targetRoot "$arm64Target\release\libaisishuwu_native.so"
$ohosArm64So = Join-Path $targetRoot "$ohosArm64Target\release\libaisishuwu_native.so"
$ohosLinker = Join-Path $crateRoot '..\..\packages\mgread_ohos_native_runtime\native\ohos-clang-linker.cmd'
$ohosCompiler = Join-Path $crateRoot '..\..\packages\mgread_ohos_native_runtime\native\ohos-clang-cc.cmd'
$environmentNames = @(
  'CARGO_INCREMENTAL',
  'RUSTFLAGS',
  'CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER',
  'CC_aarch64-linux-android',
  'CC_aarch64_linux_android'
  'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER',
  'CC_aarch64_unknown_linux_ohos',
  'AR_aarch64_unknown_linux_ohos',
  'OHOS_SDK_NATIVE',
  'MGREAD_OHOS_TARGET_ARCH'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
  [Environment]::SetEnvironmentVariable('CARGO_INCREMENTAL', '0', 'Process')
  [Environment]::SetEnvironmentVariable('RUSTFLAGS', $null, 'Process')
  Push-Location $crateRoot
  try {
    & $rustup run $toolchain cargo build --locked --release --target $windowsTarget
    if ($LASTEXITCODE -ne 0) { throw "Windows native source build failed ($LASTEXITCODE)." }

    [Environment]::SetEnvironmentVariable('CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER', $arm64Clang, 'Process')
    [Environment]::SetEnvironmentVariable('CC_aarch64-linux-android', $arm64Clang, 'Process')
    [Environment]::SetEnvironmentVariable('CC_aarch64_linux_android', $arm64Clang, 'Process')
    [Environment]::SetEnvironmentVariable('RUSTFLAGS', '-C link-arg=-Wl,-z,max-page-size=16384', 'Process')
    & $rustup run $toolchain cargo build --locked --release --target $arm64Target
    if ($LASTEXITCODE -ne 0) { throw "Android arm64 native source build failed ($LASTEXITCODE)." }

    if (-not [System.IO.Directory]::Exists($OhosSdkNative)) {
      throw "The pinned OHOS SDK native directory was not found: $OhosSdkNative"
    }
    foreach ($requiredPath in @($ohosLinker, $ohosCompiler)) {
      if (-not [System.IO.File]::Exists($requiredPath)) {
        throw "The OHOS native source linker input was not found: $requiredPath"
      }
    }
    [Environment]::SetEnvironmentVariable('OHOS_SDK_NATIVE', $OhosSdkNative, 'Process')
    [Environment]::SetEnvironmentVariable('MGREAD_OHOS_TARGET_ARCH', 'arm64', 'Process')
    [Environment]::SetEnvironmentVariable('CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER', $ohosLinker, 'Process')
    [Environment]::SetEnvironmentVariable('CC_aarch64_unknown_linux_ohos', $ohosCompiler, 'Process')
    [Environment]::SetEnvironmentVariable('AR_aarch64_unknown_linux_ohos', (Join-Path $OhosSdkNative 'llvm\bin\llvm-ar.exe'), 'Process')
    [Environment]::SetEnvironmentVariable('RUSTFLAGS', $null, 'Process')
    & $rustup run $toolchain cargo build --locked --release --target $ohosArm64Target
    if ($LASTEXITCODE -ne 0) { throw "OHOS arm64 native source build failed ($LASTEXITCODE)." }

  }
  finally {
    Pop-Location
  }

  foreach ($library in @($windowsDll, $arm64So, $ohosArm64So)) {
    if (-not [System.IO.File]::Exists($library)) {
      throw "The expected native library was not produced: $library"
    }
  }

  & (Join-Path $PSScriptRoot 'package.ps1') `
    -WindowsDll $windowsDll `
    -AndroidArm64So $arm64So `
    -OhosArm64So $ohosArm64So `
    -IncludeOhos `
    -Output $Output
}
finally {
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
  }
}
