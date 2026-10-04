# Run an OHOS integration test with a debug, architecture-specific build
# adapter. Flutter's OHOS test runner does not expose
# --target-platform, so the selected native HAR and HAP ABI must be selected
# before it starts.

param(
  [Parameter(Mandatory = $true)]
  [string]$TestPath,
  [string]$DeviceId = '127.0.0.1:5555',
  [ValidateSet('arm64', 'x64')]
  [string]$Architecture = 'arm64',
  [string]$FlutterExecutable = 'flutter',
  [int]$DdsPort = 45000,
  [string[]]$DartDefine = @()
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'ohos-build-contract.ps1')
$variant = Get-MgReadOhosVariant -BuildMode 'debug' -Architecture $Architecture
$toolchain = Get-MgReadOhosToolchain -ProjectRoot $projectRoot
Assert-MgReadOhosToolchain `
  -Toolchain $toolchain `
  -Variant $variant `
  -ProjectRoot $projectRoot
$variantRoot = Set-MgReadOhosBuildEnvironment -Toolchain $toolchain -Variant $variant -ProjectRoot $projectRoot

# Keep Flutter/Hvigor integration builds on the same compatible Node version
# as the Release HAP builder. DevEco's current Hvigor still calls the removed
# fs.rmdirSync(path, { recursive: true }) API, which fails under Node 24/26.
$mgreadNodeRoot = $toolchain.BuildNode.Root
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
  'CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER',
  'CC_aarch64_unknown_linux_ohos',
  'CC_x86_64_unknown_linux_ohos',
  'AR_aarch64_unknown_linux_ohos',
  'AR_x86_64_unknown_linux_ohos',
  'MGREAD_RUST_RUNTIME_LIB',
  'MGREAD_RUST_RUNTIME_INCLUDE',
  'MGREAD_OHOS_TARGET_ARCH',
  'CARGO_TARGET_DIR'
)
$originalRustEnvironment = @{}
foreach ($name in $rustEnvironmentNames) {
  $originalRustEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$flutterPath = Join-Path $toolchain.Flutter.Root 'bin\flutter.bat'
if ($FlutterExecutable -ne 'flutter') {
  throw 'OHOS integration tests use the pinned Flutter from toolchain.lock; custom Flutter executables are not supported.'
}
$targetPlatform = "ohos-$Architecture"
$rootPackage = Join-Path $projectRoot 'ohos\oh-package.json5'
$rootPackageLock = Join-Path $projectRoot 'ohos\oh-package-lock.json5'
$entryPackage = Join-Path $projectRoot 'ohos\entry\oh-package.json5'
$entryBuildProfile = Join-Path $projectRoot 'ohos\entry\build-profile.json5'
$runtimeBuildProfile = Join-Path $projectRoot 'packages\mgread_plugin_runtime\ohos\build-profile.json5'
$nativeRuntimeBuildProfile = Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\build-profile.json5'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "mgread-ohos-integration-$PID"
$backupRootPackage = Join-Path $temporaryRoot 'oh-package.json5'
$backupRootPackageLock = Join-Path $temporaryRoot 'oh-package-lock.json5'
$backupEntryPackage = Join-Path $temporaryRoot 'entry.oh-package.json5'
$backupEntryBuildProfile = Join-Path $temporaryRoot 'entry.build-profile.json5'
$backupRuntimeBuildProfile = Join-Path $temporaryRoot 'runtime.build-profile.json5'
$backupNativeRuntimeBuildProfile = Join-Path $temporaryRoot 'native-runtime.build-profile.json5'
$backupPackageMetadata = Join-Path $temporaryRoot 'package-metadata'
$hadRootPackageLock = Test-Path -LiteralPath $rootPackageLock -PathType Leaf

function Remove-StaleIntegrationBuildOutputs {
  $generatedPaths = @(
    (Join-Path $projectRoot 'ohos\entry\build'),
    (Join-Path $projectRoot 'ohos\entry\.cxx'),
    (Join-Path $projectRoot 'ohos\entry\src\main\resources\rawfile\flutter_assets'),
    (Join-Path $projectRoot 'ohos\oh_modules'),
    (Join-Path $projectRoot 'ohos\entry\oh_modules'),
    (Join-Path $projectRoot 'packages\mgread_plugin_runtime\ohos\build'),
    (Join-Path $projectRoot 'packages\mgread_plugin_runtime\ohos\.cxx'),
    (Join-Path $projectRoot 'packages\mgread_plugin_runtime\ohos\oh_modules'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\build'),
    (Join-Path $projectRoot 'packages\mgread_ohos_native_runtime\ohos\.cxx')
  )
  foreach ($generatedPath in $generatedPaths) {
    if (Test-Path -LiteralPath $generatedPath) {
      try {
        Remove-Item -LiteralPath $generatedPath -Recurse -Force -ErrorAction Stop
        Write-Host "Removed stale OHOS integration output: $generatedPath"
      } catch {
        Write-Warning "Keeping locked OHOS integration output; the build will reconfigure it: $generatedPath ($($_.Exception.Message))"
      }
    }
  }

  $rawfileRoot = Join-Path $projectRoot 'ohos\entry\src\main\resources\rawfile'
  if (Test-Path -LiteralPath $rawfileRoot -PathType Container) {
    Get-ChildItem -LiteralPath $rawfileRoot -Directory -Filter 'flutter_assets.stale-*' |
      ForEach-Object {
        try {
          Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
          Write-Host "Removed stale OHOS integration assets: $($_.FullName)"
        } catch {
          Write-Warning "Keeping locked OHOS integration assets: $($_.FullName) ($($_.Exception.Message))"
        }
      }
  }
}

function Set-OhosFlutterRuntimeOverrides {
  $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterPath)
  $engineDirectory = Join-Path (Join-Path $flutterRoot 'bin\cache\artifacts\engine') $targetPlatform
  $nativeName = if ($Architecture -eq 'arm64') { 'flutter_native_arm64_v8a' } else { 'flutter_native_x86_64' }
  $nativeFileName = if ($Architecture -eq 'arm64') { 'arm64_v8a_debug.har' } else { 'x86_64_debug.har' }
  $embeddingPath = Join-Path $engineDirectory 'flutter_embedding_debug.har'
  $nativePath = Join-Path $engineDirectory $nativeFileName
  foreach ($requiredPath in @($embeddingPath, $nativePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw "OHOS debug $Architecture Flutter HAR is missing: $requiredPath"
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
  Write-Host "OHOS debug $Architecture selects $nativeName and matching Flutter embedding HAR."
}

function Ensure-FlutterPackageConfig {
  $packageConfig = Join-Path $projectRoot '.dart_tool\package_config.json'
  if (Test-Path -LiteralPath $packageConfig -PathType Leaf) {
    return
  }
  Write-Host 'Flutter package_config.json is missing; running the pinned Flutter pub get.'
  Push-Location $projectRoot
  try {
    & $flutterPath pub get
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
if (-not (Test-Path -LiteralPath $rootPackage -PathType Leaf)) {
  throw "OHOS root package not found: $rootPackage"
}
if (-not (Test-Path -LiteralPath $entryBuildProfile -PathType Leaf)) {
  throw "OHOS entry build profile not found: $entryBuildProfile"
}
if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
  throw "Integration test not found: $TestPath"
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
Copy-Item -LiteralPath $rootPackage -Destination $backupRootPackage -Force
if ($hadRootPackageLock) {
  Copy-Item -LiteralPath $rootPackageLock -Destination $backupRootPackageLock -Force
}
Copy-Item -LiteralPath $entryPackage -Destination $backupEntryPackage -Force
Copy-Item -LiteralPath $entryBuildProfile -Destination $backupEntryBuildProfile -Force
Copy-Item -LiteralPath $runtimeBuildProfile -Destination $backupRuntimeBuildProfile -Force
Copy-Item -LiteralPath $nativeRuntimeBuildProfile -Destination $backupNativeRuntimeBuildProfile -Force
foreach ($metadataFile in $packageMetadataFiles) {
  $relativePath = $metadataFile.FullName.Substring($projectRoot.Length + 1)
  $backupPath = Join-Path $backupPackageMetadata $relativePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
  Copy-Item -LiteralPath $metadataFile.FullName -Destination $backupPath -Force
}
try {
  Ensure-FlutterPackageConfig
  Set-OhosFlutterRuntimeOverrides
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

  $runtimeAbi = if ($Architecture -eq 'arm64') { '"arm64-v8a"' } else { '"x86_64"' }
  foreach ($packageProfile in @($runtimeBuildProfile, $nativeRuntimeBuildProfile)) {
    $profileSource = Get-Content -LiteralPath $packageProfile -Raw
    $abiFilterPattern = '(?s)"abiFilters"\s*:\s*\[[^\]]*\]'
    if (-not [regex]::IsMatch($profileSource, $abiFilterPattern)) {
      throw "Could not find ABI filters in $packageProfile"
    }
    $updatedProfile = [regex]::Replace(
      $profileSource,
      $abiFilterPattern,
      '"abiFilters": [' + $runtimeAbi + ']',
      1
    )
    if ($updatedProfile -ne $profileSource) {
      Set-Content -LiteralPath $packageProfile -Value $updatedProfile -Encoding utf8
    }
  }

  $rustRuntime = Build-MgReadOhosRustRuntime `
    -Toolchain $toolchain `
    -ProjectRoot $projectRoot `
    -TargetDirectory (Join-Path $variantRoot 'rust-target') `
    -Architecture $Architecture
  $env:MGREAD_RUST_RUNTIME_LIB = $rustRuntime.Library
  $env:MGREAD_RUST_RUNTIME_INCLUDE = $rustRuntime.Include
  Write-Host "OHOS Rust runtime: $($rustRuntime.Library)"
  Remove-StaleIntegrationBuildOutputs

  Write-Host "Running OHOS $Architecture integration test on ${DeviceId}: $TestPath"
  $flutterArguments = @('test', $TestPath, '-d', $DeviceId, '--no-pub')
  if ($DdsPort -gt 0) {
    $flutterArguments += @('--dds-port', $DdsPort.ToString())
  }
  foreach ($define in $DartDefine) {
    $flutterArguments += "--dart-define=$define"
  }
  $flutterArguments += "--dart-define=MGREAD_OHOS_ARCH=$Architecture"
  & $flutterPath @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter integration test failed with exit code $LASTEXITCODE"
  }
} finally {
  foreach ($name in $rustEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalRustEnvironment[$name], 'Process')
  }
  $env:Path = $originalPath
  Copy-Item -LiteralPath $backupRootPackage -Destination $rootPackage -Force
  if ($hadRootPackageLock) {
    Copy-Item -LiteralPath $backupRootPackageLock -Destination $rootPackageLock -Force
  } elseif (Test-Path -LiteralPath $rootPackageLock -PathType Leaf) {
    Remove-Item -LiteralPath $rootPackageLock -Force
  }
  Copy-Item -LiteralPath $backupEntryPackage -Destination $entryPackage -Force
  Copy-Item -LiteralPath $backupEntryBuildProfile -Destination $entryBuildProfile -Force
  Copy-Item -LiteralPath $backupRuntimeBuildProfile -Destination $runtimeBuildProfile -Force
  Copy-Item -LiteralPath $backupNativeRuntimeBuildProfile -Destination $nativeRuntimeBuildProfile -Force
  if (Test-Path -LiteralPath $backupPackageMetadata -PathType Container) {
    foreach ($backupFile in (Get-ChildItem -LiteralPath $backupPackageMetadata -Recurse -File)) {
      $relativePath = $backupFile.FullName.Substring($backupPackageMetadata.Length + 1)
      $destination = Join-Path $projectRoot $relativePath
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
      Copy-Item -LiteralPath $backupFile.FullName -Destination $destination -Force
    }
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
