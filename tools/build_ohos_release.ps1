# MgRead OHOS HAP build entry point.
#
# It narrows the Flutter Runtime asset manifest, root HAR overrides, and entry
# native architecture only during the build, then restores them even when the
# build fails. Release and debug share this path so neither package gets stale
# mode/architecture artifacts or an unselected architecture.

param(
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'release',
  [ValidateSet('arm64', 'x64')]
  [string]$Architecture = 'arm64',
  [switch]$NoCodesign
)

$ErrorActionPreference = 'Stop'

# Hvigor bundled with the installed DevEco SDK still calls the removed
# fs.rmdirSync(path, { recursive: true }) API. Keep OHOS builds independent
# from the user's global Node version by using the repository toolchain on D:.
$mgreadNodeRoot = 'D:\mgread-env\node-v20.19.5-win-x64'
$mgreadNodeExecutable = Join-Path $mgreadNodeRoot 'node.exe'
if (-not (Test-Path -LiteralPath $mgreadNodeExecutable -PathType Leaf)) {
  throw "MgRead fixed Node toolchain is missing: $mgreadNodeExecutable"
}
$mgreadRuntimeNpm = 'D:\mgread-env\node-v26.10.0-win-x64\npm.cmd'
if (-not (Test-Path -LiteralPath $mgreadRuntimeNpm -PathType Leaf)) {
  throw "MgRead Runtime fixed Node toolchain is missing: $mgreadRuntimeNpm"
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
$runtimePubspec = Join-Path $projectRoot 'packages\mgread_plugin_runtime\pubspec.yaml'
$rootPackage = Join-Path $projectRoot 'ohos\oh-package.json5'
$rootPackageLock = Join-Path $projectRoot 'ohos\oh-package-lock.json5'
$entryPackage = Join-Path $projectRoot 'ohos\entry\oh-package.json5'
$entryBuildProfile = Join-Path $projectRoot 'ohos\entry\build-profile.json5'
$hapDirectory = Join-Path $projectRoot 'build\ohos\hap'
$targetPlatform = "ohos-$Architecture"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "mgread-ohos-release-$PID"
$backupPubspec = Join-Path $temporaryRoot 'mgread_plugin_runtime.pubspec.yaml'
$backupRootPackage = Join-Path $temporaryRoot 'oh-package.json5'
$backupRootPackageLock = Join-Path $temporaryRoot 'oh-package-lock.json5'
$backupEntryPackage = Join-Path $temporaryRoot 'entry.oh-package.json5'
$backupEntryBuildProfile = Join-Path $temporaryRoot 'entry.build-profile.json5'
$backupPackageMetadata = Join-Path $temporaryRoot 'package-metadata'
$hadRootPackageLock = Test-Path -LiteralPath $rootPackageLock -PathType Leaf

$packagesRoot = Join-Path $projectRoot 'packages'
$packageMetadataFiles = @()
if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
  $packageMetadataFiles = @(
    Get-ChildItem -LiteralPath $packagesRoot -Recurse -File |
      Where-Object { $_.Name -in @('BuildProfile.ets', 'oh-package-lock.json5') }
  )
}

function Remove-StaleNativeBuildModeMetadata {
  $packagesRoot = Join-Path $projectRoot 'packages'
  if (-not (Test-Path -LiteralPath $packagesRoot -PathType Container)) {
    return
  }
  $metadataFiles = Get-ChildItem -LiteralPath $packagesRoot -Recurse -File -Filter 'build_info.json' |
    Where-Object {
      $_.FullName -match '\\ohos\\build\\default\\intermediates\\build_info\\default\\meta\\build_info\.json$'
    }
  foreach ($metadataFile in $metadataFiles) {
    Remove-Item -LiteralPath $metadataFile.FullName -Force
    Write-Host "Removed stale OHOS native build-mode metadata: $($metadataFile.FullName)"
  }
}

function Remove-StaleFlutterBuildOutputs {
  $generatedPaths = @(
    (Join-Path $projectRoot 'ohos\entry\build'),
    (Join-Path $projectRoot 'ohos\entry\.cxx'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\build'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\.cxx'),
    $hapDirectory
  )
  foreach ($generatedPath in $generatedPaths) {
    if (Test-Path -LiteralPath $generatedPath) {
      Remove-Item -LiteralPath $generatedPath -Recurse -Force
      Write-Host "Removed stale OHOS Flutter output: $generatedPath"
    }
  }
}

function Set-OhosFlutterRuntimeOverrides {
  $flutterCommand = Get-Command flutter -ErrorAction Stop | Select-Object -First 1
  $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
  $engineVariant = if ($BuildMode -eq 'debug') {
    $targetPlatform
  } else {
    "$targetPlatform-release"
  }
  $engineRoot = Join-Path $flutterRoot 'bin\cache\artifacts\engine'
  $engineDirectory = Join-Path $engineRoot $engineVariant
  $nativeName = if ($Architecture -eq 'arm64') { 'flutter_native_arm64_v8a' } else { 'flutter_native_x86_64' }
  $nativeFileName = if ($Architecture -eq 'arm64') { "arm64_v8a_$BuildMode.har" } else { "x86_64_$BuildMode.har" }
  $embeddingPath = Join-Path $engineDirectory "flutter_embedding_$BuildMode.har"
  $nativePath = Join-Path $engineDirectory $nativeFileName
  foreach ($requiredPath in @($embeddingPath, $nativePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw "OHOS $BuildMode $Architecture Flutter HAR is missing: $requiredPath"
    }
  }

  $config = Get-Content -LiteralPath $rootPackage -Raw | ConvertFrom-Json
  $overrides = $config.overrides
  if ($null -eq $overrides) {
    throw "OHOS root package has no overrides map: $rootPackage"
  }
  foreach ($name in @('@ohos/flutter_ohos', 'flutter_native_arm64_v8a', 'flutter_native_x86_64')) {
    $overrides.PSObject.Properties.Remove($name)
  }
  $overrides | Add-Member -MemberType NoteProperty -Name '@ohos/flutter_ohos' -Value "file:$embeddingPath" -Force
  $overrides | Add-Member -MemberType NoteProperty -Name $nativeName -Value "file:$nativePath" -Force
  $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rootPackage -Encoding utf8
  Write-Host "OHOS $BuildMode $Architecture selects $nativeName and matching Flutter embedding HAR."
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
  $rustInclude = Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\native\rust-runtime\include'
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

if (-not (Test-Path -LiteralPath $runtimePubspec -PathType Leaf)) {
  throw "Runtime pubspec not found: $runtimePubspec"
}
if (-not (Test-Path -LiteralPath $rootPackage -PathType Leaf)) {
  throw "OHOS root package not found: $rootPackage"
}
if (-not (Test-Path -LiteralPath $entryPackage -PathType Leaf)) {
  throw "OHOS entry package not found: $entryPackage"
}
if (-not (Test-Path -LiteralPath $entryBuildProfile -PathType Leaf)) {
  throw "OHOS entry build profile not found: $entryBuildProfile"
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
Copy-Item -LiteralPath $runtimePubspec -Destination $backupPubspec -Force
Copy-Item -LiteralPath $rootPackage -Destination $backupRootPackage -Force
if ($hadRootPackageLock) {
  Copy-Item -LiteralPath $rootPackageLock -Destination $backupRootPackageLock -Force
}
Copy-Item -LiteralPath $entryPackage -Destination $backupEntryPackage -Force
Copy-Item -LiteralPath $entryBuildProfile -Destination $backupEntryBuildProfile -Force
foreach ($metadataFile in $packageMetadataFiles) {
  $relativePath = $metadataFile.FullName.Substring($projectRoot.Length + 1)
  $backupPath = Join-Path $backupPackageMetadata $relativePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
  Copy-Item -LiteralPath $metadataFile.FullName -Destination $backupPath -Force
}

try {
  $nodeRuntimeRoot = Join-Path $projectRoot 'packages\mg_read_node_runtime'
  $runtimeNodeRoot = Split-Path -Parent $mgreadRuntimeNpm
  $runtimeStagePath = $env:Path
  $env:Path = "$runtimeNodeRoot;$runtimeStagePath"
  Push-Location $nodeRuntimeRoot
  try {
    & $mgreadRuntimeNpm run stage:flutter-ohos
    if ($LASTEXITCODE -ne 0) {
      throw "OHOS Node Runtime staging failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
    $env:Path = $runtimeStagePath
  }

  $pubspec = Get-Content -LiteralPath $runtimePubspec -Raw
  $assetBlockPattern = '(?ms)^  assets:\r?\n(?:    - assets/runtime/[^\r\n]+\r?\n)+'
  $ohosAssetBlock = @(
    '  assets:',
    '    - assets/runtime/ohos/runtime-version.txt',
    '    - assets/runtime/ohos/dist/'
  ) -join "`r`n"
  $updatedPubspec = [regex]::Replace($pubspec, $assetBlockPattern, $ohosAssetBlock.TrimEnd() + "`r`n", 1)

  if ($updatedPubspec -eq $pubspec) {
    throw 'Runtime asset block was not found; stopped to avoid producing an invalid package.'
  }

  Set-Content -LiteralPath $runtimePubspec -Value $updatedPubspec -Encoding utf8
  $entrySource = Get-Content -LiteralPath $entryPackage -Raw
  $selectedArchitecture = if ($Architecture -eq 'arm64') { 'arm64_v8a' } else { 'x86_64' }
  $unselectedArchitecture = if ($Architecture -eq 'arm64') { 'x86_64' } else { 'arm64_v8a' }
  $lineEnding = if ($entrySource.Contains("`r`n")) { "`r`n" } else { "`n" }
  $architectureDependencyPattern = '(?m)^\s*"flutter_native_(?:arm64_v8a|x86_64)":.*\r?\n'
  $withoutArchitectureDependencies = [regex]::Replace($entrySource, $architectureDependencyPattern, '', 0)
  $flutterDependencyAnchor = '    "@ohos/flutter_ohos": "",'
  $selectedFlutterDependency = '    "flutter_native_' + $selectedArchitecture + '": "",'
  $updatedEntry = $withoutArchitectureDependencies.Replace(
    $flutterDependencyAnchor,
    $flutterDependencyAnchor + $lineEnding + $selectedFlutterDependency
  )
  if ($updatedEntry -eq $withoutArchitectureDependencies) {
    throw "flutter_native_$unselectedArchitecture dependency was not found; stopped to avoid a dual-architecture HAP."
  }
  Set-Content -LiteralPath $entryPackage -Value $updatedEntry -Encoding utf8
  Write-Host "OHOS $targetPlatform $BuildMode keeps only flutter_native_$selectedArchitecture and excludes the other native architecture."

  $buildProfileSource = Get-Content -LiteralPath $entryBuildProfile -Raw
  $unselectedNativeLibDirectory = if ($Architecture -eq 'arm64') { 'x86_64' } else { 'arm64-v8a' }
  $nativeLibExcludePattern = '(?m)"\*\*/(?:x86_64|arm64-v8a)/\*\.so"'
  if (-not [regex]::IsMatch($buildProfileSource, $nativeLibExcludePattern)) {
    throw 'Native library exclusion was not found; stopped to avoid producing a multi-architecture HAP.'
  }
  $updatedBuildProfile = [regex]::Replace(
    $buildProfileSource,
    $nativeLibExcludePattern,
    '"**/' + $unselectedNativeLibDirectory + '/*.so"',
    1
  )
  Set-Content -LiteralPath $entryBuildProfile -Value $updatedBuildProfile -Encoding utf8

  # The DevEco Hvigor version bundled with the current SDK calls
  # fs.rmdirSync(path, { recursive: true }) when this metadata records a
  # different build mode. Node 26 rejects that removed option. Removing the
  # generated metadata makes Hvigor configure/build the existing CMake trees
  # without entering that broken mode-switch cleanup path.
  Remove-StaleNativeBuildModeMetadata

  # Release HAPs use the accepted arm64 Rust source engine. The normal
  # development build remains Node-backed unless this explicit opt-in is set.
  $rustRuntime = Build-OhosRustRuntime -TargetArchitecture $Architecture
  if ($null -ne $rustRuntime) {
    $env:MGREAD_RUST_RUNTIME_LIB = $rustRuntime.Library
    $env:MGREAD_RUST_RUNTIME_INCLUDE = $rustRuntime.Include
    Write-Host "OHOS Rust runtime: $($rustRuntime.Library)"
  }
  Set-OhosFlutterRuntimeOverrides
  Remove-StaleFlutterBuildOutputs
  $flutterArguments = 'build', 'hap', "--$BuildMode", '--target-platform', $targetPlatform, '--no-pub', '--no-tree-shake-icons', '--dart-define=MGREAD_OHOS_NATIVE_RUNTIME=true'
  if ($NoCodesign) {
    $flutterArguments += '--no-codesign'
  }

  Push-Location $projectRoot
  try {
    & flutter @flutterArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Flutter HAP build failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $hap = Get-ChildItem -LiteralPath $hapDirectory -Filter '*.hap' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($null -eq $hap) {
    throw "Build completed but no HAP was found: $hapDirectory"
  }
  $hapEntries = tar -tf $hap.FullName
  $hasAotSnapshot = @($hapEntries | Where-Object { $_ -eq 'libs/arm64-v8a/libapp.so' -or $_ -eq 'libs/x86_64/libapp.so' }).Count -gt 0
  $hasDebugKernel = @($hapEntries | Where-Object { $_ -eq 'resources/rawfile/flutter_assets/kernel_blob.bin' }).Count -gt 0
  if ($BuildMode -eq 'release' -and (-not $hasAotSnapshot -or $hasDebugKernel)) {
    throw 'The generated Release HAP is not an AOT package; stale Debug Flutter artifacts were detected.'
  }
  $selectedArchitecturePath = if ($Architecture -eq 'arm64') { 'libs/arm64-v8a/' } else { 'libs/x86_64/' }
  $selectedArchitectureEntries = @($hapEntries | Where-Object { $_ -like "$selectedArchitecturePath*" })
  if ($selectedArchitectureEntries.Count -eq 0) {
    throw "The generated HAP does not contain the requested architecture: $selectedArchitecturePath"
  }
  $unexpectedArchitecturePath = if ($Architecture -eq 'arm64') { 'libs/x86_64/' } else { 'libs/arm64-v8a/' }
  $unexpectedArchitectureEntries = @($hapEntries | Where-Object { $_ -like "$unexpectedArchitecturePath*" })
  if ($unexpectedArchitectureEntries.Count -gt 0) {
    throw "The generated HAP still contains the unselected architecture: $unexpectedArchitecturePath"
  }
  $unselectedRuntimePatterns = @(
    'resources/rawfile/flutter_assets/packages/mgread_plugin_runtime/assets/runtime/android/',
    'resources/rawfile/flutter_assets/packages/mgread_plugin_runtime/assets/runtime/windows-x64/',
    'resources/rawfile/flutter_assets/packages/mgread_plugin_runtime/assets/runtime/macos-arm64/'
  )
  foreach ($pattern in $unselectedRuntimePatterns) {
    if ($hapEntries | Where-Object { $_ -like "$pattern*" } | Select-Object -First 1) {
      throw "The generated HAP still contains a non-OHOS Runtime: $pattern"
    }
  }
  Write-Host ("OHOS $BuildMode HAP: {0} ({1:N2} MB)" -f $hap.FullName, ($hap.Length / 1MB))
} finally {
  $env:Path = $originalPath
  foreach ($name in $rustEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalRustEnvironment[$name], 'Process')
  }
  Copy-Item -LiteralPath $backupPubspec -Destination $runtimePubspec -Force
  Copy-Item -LiteralPath $backupRootPackage -Destination $rootPackage -Force
  if ($hadRootPackageLock) {
    Copy-Item -LiteralPath $backupRootPackageLock -Destination $rootPackageLock -Force
  } elseif (Test-Path -LiteralPath $rootPackageLock -PathType Leaf) {
    Remove-Item -LiteralPath $rootPackageLock -Force
  }
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
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Restored temporary OHOS build configuration.'
}
