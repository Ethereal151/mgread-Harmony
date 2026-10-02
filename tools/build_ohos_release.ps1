# MgRead OHOS HAP build entry point.
#
# It materializes one pinned OHOS variant and leaves the selected manifests and
# locks in place. A failed build therefore remains reproducible and debuggable;
# the next invocation explicitly selects its own variant. Flutter/Hvigor and
# Runtime versions are owned by tools/ohos-build-contract.ps1.

param(
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'release',
  [ValidateSet('arm64', 'x64')]
  [string]$Architecture = 'arm64',
  [switch]$NoCodesign
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'ohos-build-contract.ps1')
$variant = Get-MgReadOhosVariant -BuildMode $BuildMode -Architecture $Architecture
$toolchain = Get-MgReadOhosToolchain -ProjectRoot $projectRoot
Assert-MgReadOhosToolchain -Toolchain $toolchain -Variant $variant -ProjectRoot $projectRoot
$variantRoot = Set-MgReadOhosBuildEnvironment -Toolchain $toolchain -Variant $variant -ProjectRoot $projectRoot

# The build host uses Node 20 for DevEco/Hvigor. Runtime asset staging is
# switched to the separately pinned Node 26 toolchain only around npm.
$mgreadNodeRoot = $toolchain.BuildNode.Root
$mgreadRuntimeNpm = Join-Path $toolchain.RuntimeNode.Root 'npm.cmd'
$originalPath = $env:Path
$env:Path = "$(Join-Path $toolchain.Flutter.Root 'bin');$mgreadNodeRoot;$originalPath"
$selectedFlutterRoot = $toolchain.Flutter.Root
$selectedFlutterRootLeaf = Split-Path -Leaf $selectedFlutterRoot
$flutter = Join-Path $toolchain.Flutter.Root 'bin\flutter.bat'
$rustEnvironmentNames = @(
  'CARGO_HOME',
  'RUSTUP_HOME',
  'OHOS_SDK_NATIVE',
  'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER',
  'CC_aarch64_unknown_linux_ohos',
  'AR_aarch64_unknown_linux_ohos',
  'MGREAD_RUST_RUNTIME_LIB',
  'MGREAD_RUST_RUNTIME_INCLUDE',
  'MGREAD_NODE_ROOT',
  'MGREAD_NODE_SOURCE_ROOT',
  'MGREAD_OHOS_VARIANT',
  'CARGO_TARGET_DIR'
)
$originalRustEnvironment = @{}
foreach ($name in $rustEnvironmentNames) {
  $originalRustEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$runtimePubspec = Join-Path $projectRoot 'packages\mgread_plugin_runtime\pubspec.yaml'
$rootPackage = Join-Path $projectRoot 'ohos\oh-package.json5'
$rootPackageLock = Join-Path $projectRoot 'ohos\oh-package-lock.json5'
$entryPackage = Join-Path $projectRoot 'ohos\entry\oh-package.json5'
$entryPackageLock = Join-Path $projectRoot 'ohos\entry\oh-package-lock.json5'
$entryBuildProfile = Join-Path $projectRoot 'ohos\entry\build-profile.json5'
$hapDirectory = Join-Path $projectRoot 'build\ohos\hap'
$targetPlatform = $variant.TargetPlatform
$variantLockRoot = Join-Path $variantRoot 'locks'
$variantOutputRoot = Join-Path $variantRoot 'output'
$hadRootPackageLock = Test-Path -LiteralPath $rootPackageLock -PathType Leaf
$hadEntryPackageLock = Test-Path -LiteralPath $entryPackageLock -PathType Leaf

$packagesRoot = Join-Path $projectRoot 'packages'
$packageMetadataFiles = @()
if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
  $packageMetadataFiles = @(
    Get-ChildItem -LiteralPath $packagesRoot -Recurse -File |
      Where-Object { $_.Name -in @('BuildProfile.ets', 'oh-package-lock.json5') }
  )
}
$packageBuildProfileFiles = @()
if (Test-Path -LiteralPath $packagesRoot -PathType Container) {
  $packageBuildProfileFiles = @(
    Get-ChildItem -LiteralPath $packagesRoot -Recurse -File -Filter 'build-profile.json5' |
      Where-Object {
        (Get-Content -LiteralPath $_.FullName -Raw) -match '"abiFilters"'
      }
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
    # Flutter's OHOS task stores app.dill/kernel outputs under the root build
    # tree. They are mode- and Dart-kernel-version-specific and must not be
    # reused across release/debug or SDK updates.
    (Join-Path $projectRoot 'build\ohos\intermediates'),
    # Native asset hooks also cache Dart kernel files. A cache produced by a
    # different Flutter/Dart SDK cannot be loaded by the current frontend.
    (Join-Path $projectRoot '.dart_tool\hooks_runner'),
    (Join-Path $projectRoot '.dart_tool\flutter_build'),
    (Join-Path $projectRoot 'ohos\entry\build'),
    (Join-Path $projectRoot 'ohos\entry\.cxx'),
    # ohpm materializes this tree from package locks. Keeping it across an
    # architecture/mode build preserves the previous Flutter HAR path in
    # ohos/oh_modules/.ohpm/lock.json5 and makes ProcessRouterMap resolve a
    # deleted remote package before Hvigor sees the selected lock overrides.
    (Join-Path $projectRoot 'ohos\oh_modules'),
    (Join-Path $projectRoot 'ohos\entry\oh_modules'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\build'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\.cxx'),
    (Join-Path $projectRoot 'packages\mgread_plugin_runtime\ohos\build'),
    (Join-Path $projectRoot 'packages\mgread_plugin_runtime\ohos\.cxx'),
    $hapDirectory
  )
  foreach ($generatedPath in $generatedPaths) {
    if (Test-Path -LiteralPath $generatedPath) {
      Remove-Item -LiteralPath $generatedPath -Recurse -Force
      Write-Host "Removed stale OHOS Flutter output: $generatedPath"
    }
  }
}

function Set-OhosNativeBuildProfileArchitecture {
  $selectedAbi = if ($Architecture -eq 'arm64') { 'arm64-v8a' } else { 'x86_64' }
  $abiArrayPattern = '(?s)"abiFilters"\s*:\s*\[(?<values>.*?)\]'
  foreach ($profileFile in $packageBuildProfileFiles) {
    $source = Get-Content -LiteralPath $profileFile.FullName -Raw
    $match = [regex]::Match($source, $abiArrayPattern)
    if (-not $match.Success) {
      throw "Native architecture filters were not recognized in: $($profileFile.FullName)"
    }
    $currentValues = $match.Groups['values'].Value
    $normalizedValues = $currentValues.Trim().Trim('"', "'").Trim()
    $selectedAbiPresent = $currentValues -match [regex]::Escape($selectedAbi)
    $unselectedAbi = if ($selectedAbi -eq 'arm64-v8a') { 'x86_64' } else { 'arm64-v8a' }
    $unselectedAbiPresent = $currentValues -match [regex]::Escape($unselectedAbi)
    if (-not $selectedAbiPresent -and -not $unselectedAbiPresent -and $normalizedValues.Length -gt 0) {
      throw "Native architecture filters contain no recognized ABI for $($profileFile.FullName)"
    }
    if ($selectedAbiPresent -and -not $unselectedAbiPresent) {
      Write-Host "OHOS native build profile already keeps only ${selectedAbi}: $($profileFile.FullName)"
      continue
    }
    $updated = [regex]::Replace(
      $source,
      $abiArrayPattern,
      ('"abiFilters": ["' + $selectedAbi + '"]'),
      1
    )
    Set-Content -LiteralPath $profileFile.FullName -Value $updated -Encoding utf8
    Write-Host "OHOS native build profile keeps only ${selectedAbi}: $($profileFile.FullName)"
  }
}

function Set-OhosBuildModeMetadata {
  $buildModeFiles = @(
    Get-ChildItem -LiteralPath $packagesRoot -Recurse -File -Filter 'BuildProfile.ets' -ErrorAction SilentlyContinue
  )
  $debugLiteral = if ($BuildMode -eq 'debug') { 'true' } else { 'false' }
  foreach ($modeFile in $buildModeFiles) {
    $source = Get-Content -LiteralPath $modeFile.FullName -Raw
    $updated = $source -replace "export const BUILD_MODE_NAME = '(?:debug|profile|release)';", "export const BUILD_MODE_NAME = '$BuildMode';"
    $updated = $updated -replace 'export const DEBUG = (?:true|false);', "export const DEBUG = $debugLiteral;"
    if ($updated -ne $source) {
      Set-Content -LiteralPath $modeFile.FullName -Value $updated -Encoding utf8
      Write-Host "OHOS $BuildMode metadata: $($modeFile.FullName)"
    }
  }
}

function Select-OhosVariantLocks {
  if (-not (Test-Path -LiteralPath $variantLockRoot -PathType Container)) {
    return
  }
  foreach ($metadataFile in $packageMetadataFiles) {
    $relativePath = $metadataFile.FullName.Substring($projectRoot.Length + 1)
    $savedPath = Join-Path $variantLockRoot $relativePath
    if (Test-Path -LiteralPath $savedPath -PathType Leaf) {
      Copy-Item -LiteralPath $savedPath -Destination $metadataFile.FullName -Force
    }
  }
  foreach ($lockFile in @($rootPackageLock, $entryPackageLock)) {
    $savedPath = Join-Path $variantLockRoot ([IO.Path]::GetRelativePath($projectRoot, $lockFile))
    if (Test-Path -LiteralPath $savedPath -PathType Leaf) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $lockFile) | Out-Null
      Copy-Item -LiteralPath $savedPath -Destination $lockFile -Force
    }
  }
}

function Save-OhosVariantLocks {
  New-Item -ItemType Directory -Force -Path $variantLockRoot | Out-Null
  foreach ($metadataFile in $packageMetadataFiles) {
    $relativePath = $metadataFile.FullName.Substring($projectRoot.Length + 1)
    $savedPath = Join-Path $variantLockRoot $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $savedPath) | Out-Null
    Copy-Item -LiteralPath $metadataFile.FullName -Destination $savedPath -Force
  }
  foreach ($lockFile in @($rootPackageLock, $entryPackageLock)) {
    if (-not (Test-Path -LiteralPath $lockFile -PathType Leaf)) {
      continue
    }
    $savedPath = Join-Path $variantLockRoot ([IO.Path]::GetRelativePath($projectRoot, $lockFile))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $savedPath) | Out-Null
    Copy-Item -LiteralPath $lockFile -Destination $savedPath -Force
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

function Set-OhosPackageLockOverrides {
  $engineDirectoryName = if ($BuildMode -eq 'debug') {
    $targetPlatform
  } else {
    "$targetPlatform-release"
  }
  $nativeName = if ($Architecture -eq 'arm64') { 'flutter_native_arm64_v8a' } else { 'flutter_native_x86_64' }
  $nativeHarName = if ($Architecture -eq 'arm64') {
    "arm64_v8a_$BuildMode.har"
  } else {
    "x86_64_$BuildMode.har"
  }
  $embeddingHarName = "flutter_embedding_$BuildMode.har"

  $lockFiles = @(
    @($packageMetadataFiles | Where-Object { $_.Name -eq 'oh-package-lock.json5' }) +
    @(
      if (Test-Path -LiteralPath $rootPackageLock -PathType Leaf) { Get-Item -LiteralPath $rootPackageLock }
      if (Test-Path -LiteralPath $entryPackageLock -PathType Leaf) { Get-Item -LiteralPath $entryPackageLock }
    )
  )
  foreach ($metadataFile in $lockFiles) {
    $source = Get-Content -LiteralPath $metadataFile.FullName -Raw
    $updated = $source
    # Locks are generated artifacts, but leaving the old architecture in them
    # makes ohpm select the previous HAR even after the package manifest was
    # narrowed. Rewrite the active variant lock; a successful build snapshots
    # it under the variant-specific .mgread-build directory.
    $updated = $updated -replace 'flutter_native_(?:arm64_v8a|x86_64)', $nativeName
    # oh-package-lock.json5 stores the Flutter SDK as a path relative to each
    # package. Keep that path rooted at the SDK selected above. Replacing it
    # with a hard-coded directory makes the generated root lock point at a
    # different SDK and leaves a stale x64/debug HAR for ProcessRouterMap.
    $updated = $updated -replace 'f(?:-ohos-3449)?(?=/bin|/packages)', $selectedFlutterRootLeaf
    $updated = $updated -replace 'ohos-(?:arm64|x64)(?:-profile|-release)?', $engineDirectoryName
    $updated = $updated -replace 'flutter_embedding_(?:debug|profile|release)\.har', $embeddingHarName
    $updated = $updated -replace '(?:arm64_v8a|x86_64)_(?:debug|profile|release)\.har', $nativeHarName
    if ($updated -ne $source) {
      Set-Content -LiteralPath $metadataFile.FullName -Value $updated -Encoding utf8
    }
  }
}

function Ensure-OhosLocalPluginOverrides {
  $config = Get-Content -LiteralPath $rootPackage -Raw | ConvertFrom-Json
  $overrides = $config.overrides
  if ($null -eq $overrides) {
    return
  }

  $rootDirectory = Split-Path -Parent $rootPackage
  foreach ($property in @($overrides.PSObject.Properties)) {
    if ($property.Value -isnot [string] -or $property.Value -notmatch '^file:plugins/\.flutter_ohos_plugins/([^/]+)/ohos$') {
      continue
    }
    $pluginName = $Matches[1]
    $localPluginPath = Join-Path $packagesRoot "$pluginName\ohos"
    if (-not (Test-Path -LiteralPath $localPluginPath -PathType Container)) {
      continue
    }
    $relativePluginPath = [IO.Path]::GetRelativePath($rootDirectory, $localPluginPath).Replace('\', '/')
    $property.Value = "file:$relativePluginPath"
    Write-Host "OHOS local plugin override uses the checked-out package: $pluginName"
  }
  $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rootPackage -Encoding utf8
  $writtenRootPackage = Get-Content -LiteralPath $rootPackage -Raw
  if ($writtenRootPackage -match 'file:plugins/\.flutter_ohos_plugins/') {
    throw 'OHOS root package still contains an unresolved generated plugin bridge path.'
  }
}

function Ensure-FlutterPackageConfig {
  $packageConfig = Join-Path $projectRoot '.dart_tool\package_config.json'
  if (Test-Path -LiteralPath $packageConfig -PathType Leaf) {
    return
  }
  Write-Host 'Flutter package_config.json is missing; running the pinned Flutter pub get.'
  Push-Location $projectRoot
  try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
      throw "Flutter pub get failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
  if (-not (Test-Path -LiteralPath $packageConfig -PathType Leaf)) {
    throw "Flutter pub get completed without producing: $packageConfig"
  }
}

function Install-OhosDependencies {
  # Materialized oh_modules are variant-local in the lock/cache contract. The
  # project path is still shared by Hvigor, so stale materialization is removed
  # before installing the selected lock set.
  Push-Location (Join-Path $projectRoot 'ohos')
  try {
    $entryManifestBeforeInstall = Get-Content -LiteralPath (Join-Path $projectRoot 'ohos\entry\oh-package.json5') -Raw
    $entryLockBeforeInstall = Get-Content -LiteralPath (Join-Path $projectRoot 'ohos\entry\oh-package-lock.json5') -Raw
    Write-Host ("OHOS entry dependency selection: manifest arm64={0}, x64={1}; lock arm64={2}, x64={3}" -f `
      ($entryManifestBeforeInstall -match 'flutter_native_arm64_v8a'),
      ($entryManifestBeforeInstall -match 'flutter_native_x86_64'),
      ($entryLockBeforeInstall -match 'flutter_native_arm64_v8a'),
      ($entryLockBeforeInstall -match 'flutter_native_x86_64'))
    & ohpm install --all --no-save --lockfile_stable_order `
      --cache (Join-Path $variantRoot 'ohpm-cache') --enable_cross_process_lock
    if ($LASTEXITCODE -ne 0) {
      throw "OHOS ohpm install --all failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $entryModules = Join-Path $projectRoot 'ohos\entry\oh_modules'
  if (-not (Test-Path -LiteralPath $entryModules -PathType Container)) {
    throw "OHOS dependency installation completed without producing: $entryModules"
  }
  $selectedNativeModule = if ($Architecture -eq 'arm64') {
    'flutter_native_arm64_v8a'
  } else {
    'flutter_native_x86_64'
  }
  $unselectedNativeModule = if ($Architecture -eq 'arm64') {
    'flutter_native_x86_64'
  } else {
    'flutter_native_arm64_v8a'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $entryModules '@ohos\flutter_ohos'))) {
    throw 'OHOS entry dependency installation did not materialize @ohos/flutter_ohos.'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $entryModules $selectedNativeModule))) {
    throw "OHOS entry dependency installation did not materialize $selectedNativeModule."
  }
  if (Test-Path -LiteralPath (Join-Path $entryModules $unselectedNativeModule)) {
    throw "OHOS entry dependency installation materialized the unselected architecture: $unselectedNativeModule"
  }
}

function Build-OhosRustRuntime {
  param([string]$TargetArchitecture)

  if ($TargetArchitecture -ne 'arm64') {
    return $null
  }

  $rustRoot = $toolchain.Rust.Root
  $cargoExecutable = Join-Path $rustRoot 'cargo\bin\cargo.exe'
  $rustToolchainBin = Join-Path $rustRoot "rustup\toolchains\$($toolchain.Rust.Toolchain)\bin"
  $rustProject = Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\native\rust-runtime'
  $env:CARGO_TARGET_DIR = Join-Path $variantRoot 'rust-target'
  $rustTarget = Join-Path $env:CARGO_TARGET_DIR 'aarch64-unknown-linux-ohos\release\libmgread_rust_runtime.so'
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
  $env:OHOS_SDK_NATIVE = Join-Path $toolchain.Harmony.SdkRoot 'openharmony\native'
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

function Assert-OhosAotToolchainCompatibility {
  if ($BuildMode -eq 'debug') {
    return
  }

  $flutterCommand = Get-Command flutter -ErrorAction Stop | Select-Object -First 1
  $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
  $ohosRuntimeRoot = Join-Path $flutterRoot 'bin\cache\dart-sdk-ohos'
  if (-not (Test-Path -LiteralPath $ohosRuntimeRoot -PathType Container)) {
    # Flutter 3.44.9+ohos stores the matching runtime in the normal Dart SDK
    # directory; newer OHOS bundles expose the same runtime as dart-sdk-ohos.
    $ohosRuntimeRoot = Join-Path $flutterRoot 'bin\cache\dart-sdk'
  }
  $dartRuntime = Join-Path $ohosRuntimeRoot 'bin\dartaotruntime.exe'
  $aotTool = Join-Path $flutterRoot "bin\cache\artifacts\engine\$targetPlatform-release\windows-x64\gen_snapshot.exe"
  foreach ($requiredPath in @($dartRuntime, $aotTool)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw "OHOS release toolchain input is missing: $requiredPath"
    }
  }

  $runtimeVersionOutput = (& $dartRuntime --version 2>&1 | Out-String).Trim()
  $runtimeVersionMatch = [regex]::Match($runtimeVersionOutput, 'Dart SDK version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
  if (-not $runtimeVersionMatch.Success) {
    throw "Unable to read OHOS dartaotruntime Dart version from $dartRuntime. Output: $runtimeVersionOutput"
  }
  $expectedVersion = $runtimeVersionMatch.Groups[1].Value
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $aotVersionOutput = (& $aotTool --version 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $previousErrorActionPreference
  $aotVersionMatch = [regex]::Match($aotVersionOutput, 'Dart SDK version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
  if (-not $aotVersionMatch.Success) {
    throw "Unable to read OHOS gen_snapshot Dart version from $aotTool. Output: $aotVersionOutput"
  }
  $aotVersion = $aotVersionMatch.Groups[1].Value
  if ($expectedVersion -ne $aotVersion) {
    throw @"
OHOS release toolchain is not internally compatible.
  frontend_server/dartaotruntime: Dart $expectedVersion ($ohosRuntimeRoot)
  gen_snapshot: Dart $aotVersion ($aotTool)
The HAP cannot be built safely until these two versions match; refusing to stage or mutate the project.
"@
  }
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

Assert-OhosAotToolchainCompatibility

try {
  Ensure-FlutterPackageConfig
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

  # Runtime assets stay platform-complete in pubspec.yaml. The permanent
  # Hvigor adapter removes non-OHOS runtime trees from the selected HAP.
  Select-OhosVariantLocks
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
  Set-OhosPackageLockOverrides
  $expectedEngineDirectoryName = if ($BuildMode -eq 'debug') {
    $targetPlatform
  } else {
    "$targetPlatform-release"
  }
  $expectedEmbeddingHarName = "flutter_embedding_$BuildMode.har"
  $expectedNativeHarName = if ($Architecture -eq 'arm64') {
    "arm64_v8a_$BuildMode.har"
  } else {
    "x86_64_$BuildMode.har"
  }
  $entryLockSource = Get-Content -LiteralPath $entryPackageLock -Raw
  $requiredLockTokens = @(
    $selectedFlutterRootLeaf,
    $expectedEngineDirectoryName,
    $expectedEmbeddingHarName,
    $expectedNativeHarName
  )
  foreach ($requiredLockToken in $requiredLockTokens) {
    if ($entryLockSource -notmatch [regex]::Escape($requiredLockToken)) {
      throw "OHOS entry package lock does not select the requested Flutter package: $requiredLockToken"
    }
  }
  if ($BuildMode -eq 'release' -and $entryLockSource -match 'ohos-x64|ohos-arm64(?!-release)|flutter_embedding_debug\.har|(?:arm64_v8a|x86_64)_debug\.har') {
    throw 'OHOS release entry package lock still contains a debug or unselected architecture Flutter package.'
  }
  Set-OhosNativeBuildProfileArchitecture
  Set-OhosBuildModeMetadata
  Set-Content -LiteralPath (Join-Path $variantRoot 'variant.json') -Value (
    [ordered]@{
      id = $variant.Id
      flutter = $toolchain.Flutter.Version
      dart = $toolchain.Flutter.DartVersion
      buildNode = $toolchain.BuildNode.Version
      runtimeNode = $toolchain.RuntimeNode.Version
      targetPlatform = $targetPlatform
      abi = $variant.Abi
      mode = $BuildMode
    } | ConvertTo-Json
  ) -Encoding utf8

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
  Ensure-OhosLocalPluginOverrides
  Remove-StaleFlutterBuildOutputs
  Install-OhosDependencies
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
  $selectedSqlitePath = $selectedArchitecturePath + 'libsqlite3.so'
  if (-not ($hapEntries -contains $selectedSqlitePath)) {
    throw "The generated HAP is missing the selected architecture SQLite runtime: $selectedSqlitePath"
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
  New-Item -ItemType Directory -Force -Path $variantOutputRoot | Out-Null
  $variantHap = Join-Path $variantOutputRoot $hap.Name
  Copy-Item -LiteralPath $hap.FullName -Destination $variantHap -Force
  Save-OhosVariantLocks
  Write-Host ("OHOS $BuildMode HAP: {0} ({1:N2} MB)" -f $hap.FullName, ($hap.Length / 1MB))
} finally {
  $env:Path = $originalPath
  foreach ($name in $rustEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalRustEnvironment[$name], 'Process')
  }
  Write-Host "OHOS build contract retained for variant $($variant.Id); locks and manifests remain selected."
}
