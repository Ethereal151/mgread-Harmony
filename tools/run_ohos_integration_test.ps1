# Run an OHOS integration test with an architecture-specific temporary project
# configuration. Flutter's OHOS test runner does not expose --target-platform,
# so the selected native HAR and HAP ABI must be selected before it starts.

param(
  [Parameter(Mandatory = $true)]
  [string]$TestPath,
  [string]$DeviceId = '127.0.0.1:5555',
  [ValidateSet('arm64', 'x64')]
  [string]$Architecture = 'arm64',
  [string[]]$DartDefine = @()
)

$ErrorActionPreference = 'Stop'

# Keep Flutter/Hvigor integration builds on the same compatible Node version
# as the Release HAP builder. DevEco's current Hvigor still calls the removed
# fs.rmdirSync(path, { recursive: true }) API, which fails under Node 24/26.
$mgreadNodeRoot = 'D:\mgread-env\node-v20.19.5-win-x64'
$mgreadNodeExecutable = Join-Path $mgreadNodeRoot 'node.exe'
if (-not (Test-Path -LiteralPath $mgreadNodeExecutable -PathType Leaf)) {
  throw "MgRead fixed Node toolchain is missing: $mgreadNodeExecutable"
}
$originalPath = $env:Path
$env:Path = "$mgreadNodeRoot;$originalPath"
$rustEnvironmentNames = @(
  'CARGO_HOME',
  'RUSTUP_HOME',
  'OHOS_SDK_NATIVE',
  'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER',
  'CC_aarch64_unknown_linux_ohos',
  'AR_aarch64_unknown_linux_ohos',
  'MGREAD_RUST_RUNTIME_LIB',
  'MGREAD_RUST_RUNTIME_INCLUDE'
)
$originalRustEnvironment = @{}
foreach ($name in $rustEnvironmentNames) {
  $originalRustEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$entryPackage = Join-Path $projectRoot 'ohos\entry\oh-package.json5'
$entryBuildProfile = Join-Path $projectRoot 'ohos\entry\build-profile.json5'
$entryNativeLibraries = Join-Path $projectRoot 'ohos\entry\libs'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "mgread-ohos-integration-$PID"
$backupEntryPackage = Join-Path $temporaryRoot 'entry.oh-package.json5'
$backupEntryBuildProfile = Join-Path $temporaryRoot 'entry.build-profile.json5'
$backupEntryNativeLibraries = Join-Path $temporaryRoot 'libs'
$backupPackageMetadata = Join-Path $temporaryRoot 'package-metadata'

function Remove-StaleIntegrationBuildOutputs {
  $generatedPaths = @(
    (Join-Path $projectRoot 'ohos\entry\build'),
    (Join-Path $projectRoot 'ohos\entry\.cxx'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\build'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\.cxx')
  )
  foreach ($generatedPath in $generatedPaths) {
    if (Test-Path -LiteralPath $generatedPath) {
      Remove-Item -LiteralPath $generatedPath -Recurse -Force
      Write-Host "Removed stale OHOS integration output: $generatedPath"
    }
  }
}

function Build-OhosRustRuntime {
  param([string]$TargetArchitecture)

  if ($TargetArchitecture -ne 'arm64') {
    return $null
  }

  $rustRoot = 'D:\rust'
  $cargoExecutable = Join-Path $rustRoot 'cargo\bin\cargo.exe'
  $rustToolchainBin = Join-Path $rustRoot 'rustup\toolchains\1.97.1-x86_64-pc-windows-msvc\bin'
  $rustProject = Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\native\rust-runtime'
  $rustTarget = Join-Path $rustProject 'target\aarch64-unknown-linux-ohos\release\libmgread_rust_runtime.so'
  $rustInclude = Join-Path $rustProject 'include'
  $rustLinker = Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\native\ohos-clang-linker.cmd'
  $rustCompiler = Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\native\ohos-clang-cc.cmd'

  foreach ($requiredPath in @($cargoExecutable, $rustProject, $rustLinker, $rustCompiler, (Join-Path $rustInclude 'mgread_runtime.h'))) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "OHOS Rust runtime build input is missing: $requiredPath"
    }
  }

  $env:CARGO_HOME = Join-Path $rustRoot 'cargo'
  $env:RUSTUP_HOME = Join-Path $rustRoot 'rustup'
  $env:Path = "$rustRoot\cargo\bin;$rustToolchainBin;$env:Path"
  $env:OHOS_SDK_NATIVE = 'D:\DevEco Studio\sdk\default\openharmony\native'
  $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER = $rustLinker
  $env:CC_aarch64_unknown_linux_ohos = $rustCompiler
  $env:AR_aarch64_unknown_linux_ohos = Join-Path $env:OHOS_SDK_NATIVE 'llvm\bin\llvm-ar.exe'

  Push-Location $rustProject
  try {
    & $cargoExecutable build --locked --release --target aarch64-unknown-linux-ohos
    if ($LASTEXITCODE -ne 0) {
      throw "OHOS Rust runtime build failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
  if (-not (Test-Path -LiteralPath $rustTarget -PathType Leaf)) {
    throw "OHOS Rust runtime build completed without producing: $rustTarget"
  }
  return @{ Library = $rustTarget; Include = $rustInclude }
}

function Get-HdcForwardRules {
  if (-not $hdcCommand) {
    return @()
  }
  $rules = @()
  foreach ($line in (& $hdcCommand.Source -t $DeviceId fport ls 2>$null)) {
    $match = [regex]::Match([string]$line, '^\S+\s+(tcp:\d+)\s+(tcp:\d+)')
    if ($match.Success) {
      $rules += "$($match.Groups[1].Value)|$($match.Groups[2].Value)"
    }
  }
  return $rules
}

$hdcCommand = Get-Command hdc -ErrorAction SilentlyContinue
$initialHdcForwardRules = @(Get-HdcForwardRules)
$packageMetadataFiles = @()
$packagesRoot = Join-Path $projectRoot 'packages'
if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
  $packageMetadataFiles = @(
    Get-ChildItem -LiteralPath $packagesRoot -Recurse -File |
      Where-Object { $_.Name -in @('BuildProfile.ets', 'oh-package-lock.json5') }
  )
}

if (-not (Test-Path -LiteralPath $entryPackage -PathType Leaf)) {
  throw "OHOS entry package not found: $entryPackage"
}
if (-not (Test-Path -LiteralPath $entryBuildProfile -PathType Leaf)) {
  throw "OHOS entry build profile not found: $entryBuildProfile"
}
if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
  throw "Integration test not found: $TestPath"
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
Copy-Item -LiteralPath $entryPackage -Destination $backupEntryPackage -Force
Copy-Item -LiteralPath $entryBuildProfile -Destination $backupEntryBuildProfile -Force
foreach ($metadataFile in $packageMetadataFiles) {
  $relativePath = $metadataFile.FullName.Substring($projectRoot.Length + 1)
  $backupPath = Join-Path $backupPackageMetadata $relativePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
  Copy-Item -LiteralPath $metadataFile.FullName -Destination $backupPath -Force
}
if (Test-Path -LiteralPath $entryNativeLibraries -PathType Container) {
  Copy-Item -LiteralPath $entryNativeLibraries -Destination $backupEntryNativeLibraries -Recurse -Force
}

try {
  $selectedArchitecture = if ($Architecture -eq 'arm64') { 'arm64_v8a' } else { 'x86_64' }
  $unselectedArchitecture = if ($Architecture -eq 'arm64') { 'x86_64' } else { 'arm64_v8a' }

  $entrySource = Get-Content -LiteralPath $entryPackage -Raw
  $lineEnding = if ($entrySource.Contains("`r`n")) { "`r`n" } else { "`n" }
  $dependencyPattern = '(?m)^\s*"flutter_native_(?:arm64_v8a|x86_64)":.*\r?\n'
  $withoutArchitectureDependencies = [regex]::Replace($entrySource, $dependencyPattern, '', 0)
  $flutterDependencyAnchor = '    "@ohos/flutter_ohos": "",'
  $selectedFlutterDependency = '    "flutter_native_' + $selectedArchitecture + '": "",'
  $updatedEntry = $withoutArchitectureDependencies.Replace(
    $flutterDependencyAnchor,
    $flutterDependencyAnchor + $lineEnding + $selectedFlutterDependency
  )
  if ($updatedEntry -eq $withoutArchitectureDependencies) {
    throw "Could not select flutter_native_$selectedArchitecture in $entryPackage"
  }
  Set-Content -LiteralPath $entryPackage -Value $updatedEntry -Encoding utf8

  $buildProfileSource = Get-Content -LiteralPath $entryBuildProfile -Raw
  $nativeLibExcludePattern = '(?m)"\*\*/(?:x86_64|arm64-v8a)/\*\.so"'
  if (-not [regex]::IsMatch($buildProfileSource, $nativeLibExcludePattern)) {
    throw "Native library exclusion was not found in $entryBuildProfile"
  }
  $unselectedNativeLibDirectory = if ($Architecture -eq 'arm64') { 'x86_64' } else { 'arm64-v8a' }
  $updatedBuildProfile = [regex]::Replace(
    $buildProfileSource,
    $nativeLibExcludePattern,
    '"**/' + $unselectedNativeLibDirectory + '/*.so"',
    1
  )
  Set-Content -LiteralPath $entryBuildProfile -Value $updatedBuildProfile -Encoding utf8

  $rustRuntime = Build-OhosRustRuntime -TargetArchitecture $Architecture
  if ($null -ne $rustRuntime) {
    $env:MGREAD_RUST_RUNTIME_LIB = $rustRuntime.Library
    $env:MGREAD_RUST_RUNTIME_INCLUDE = $rustRuntime.Include
    Write-Host "OHOS Rust runtime: $($rustRuntime.Library)"
  }
  Remove-StaleIntegrationBuildOutputs

  Write-Host "Running OHOS $Architecture integration test on ${DeviceId}: $TestPath"
  $flutterArguments = @('test', $TestPath, '-d', $DeviceId, '--no-pub')
  foreach ($define in $DartDefine) {
    $flutterArguments += "--dart-define=$define"
  }
  & flutter @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter integration test failed with exit code $LASTEXITCODE"
  }
} finally {
  foreach ($name in $rustEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalRustEnvironment[$name], 'Process')
  }
  $env:Path = $originalPath
  Copy-Item -LiteralPath $backupEntryPackage -Destination $entryPackage -Force
  Copy-Item -LiteralPath $backupEntryBuildProfile -Destination $entryBuildProfile -Force
  if (Test-Path -LiteralPath $backupPackageMetadata -PathType Container) {
    foreach ($backupFile in (Get-ChildItem -LiteralPath $backupPackageMetadata -Recurse -File)) {
      $relativePath = $backupFile.FullName.Substring($backupPackageMetadata.Length + 1)
      $destination = Join-Path $projectRoot $relativePath
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
      Copy-Item -LiteralPath $backupFile.FullName -Destination $destination -Force
    }
  }
  if (Test-Path -LiteralPath $backupEntryNativeLibraries -PathType Container) {
    if (Test-Path -LiteralPath $entryNativeLibraries -PathType Container) {
      Remove-Item -LiteralPath $entryNativeLibraries -Recurse -Force
    }
    Copy-Item -LiteralPath $backupEntryNativeLibraries -Destination $entryNativeLibraries -Recurse -Force
  }
  foreach ($rule in (Get-HdcForwardRules)) {
    if ($initialHdcForwardRules -notcontains $rule) {
      $parts = $rule.Split('|')
      & $hdcCommand.Source -t $DeviceId fport rm $parts[0] $parts[1] 2>$null | Out-Null
    }
  }
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Restored temporary OHOS integration-test configuration.'
}
