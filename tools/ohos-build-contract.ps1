# MgRead OHOS build contract.
#
# This is the only mutable build-adapter input for OHOS.  The Flutter/Hvigor
# project files are materialized for the requested variant, and the generated
# locks remain on that variant after a build so a failed build is diagnosable.
# Do not add toolchain fallbacks here: a missing or mismatched toolchain must
# fail before any project metadata is touched.

$ErrorActionPreference = 'Stop'

function Get-MgReadToolchainValue {
  param(
    [Parameter(Mandatory = $true)][string]$LockText,
    [Parameter(Mandatory = $true)][string]$Section,
    [Parameter(Mandatory = $true)][string]$Key
  )

  $sectionMatch = [regex]::Match(
    $LockText,
    "(?ms)^\[$([regex]::Escape($Section))\]\s*(?<body>.*?)(?=^\[|\z)"
  )
  if (-not $sectionMatch.Success) {
    throw "toolchain.lock is missing section [$Section]."
  }
  $valueMatch = [regex]::Match(
    $sectionMatch.Groups['body'].Value,
    "(?m)^$([regex]::Escape($Key))\s*=\s*(?<value>[^#\r\n]+)"
  )
  if (-not $valueMatch.Success) {
    throw "toolchain.lock is missing [$Section].$Key."
  }
  return $valueMatch.Groups['value'].Value.Trim().Trim('"').Replace('\\', '\')
}

function Get-MgReadOhosToolchain {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $lockPath = Join-Path $ProjectRoot 'toolchain.lock'
  if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Pinned toolchain contract is missing: $lockPath"
  }
  $lockText = Get-Content -LiteralPath $lockPath -Raw
  $flutter = [ordered]@{
    Root = Get-MgReadToolchainValue $lockText 'flutter' 'sdk_path'
    Version = Get-MgReadToolchainValue $lockText 'flutter' 'version'
    FrameworkRevision = Get-MgReadToolchainValue $lockText 'flutter' 'framework_revision'
    EngineRevision = Get-MgReadToolchainValue $lockText 'flutter' 'engine_revision'
    DartVersion = Get-MgReadToolchainValue $lockText 'flutter' 'dart_version'
  }
  $buildNode = [ordered]@{
    Root = Get-MgReadToolchainValue $lockText 'build' 'node_path'
    Version = Get-MgReadToolchainValue $lockText 'build' 'node_version'
    NpmVersion = Get-MgReadToolchainValue $lockText 'build' 'npm_version'
  }
  $runtimeNode = [ordered]@{
    Root = Get-MgReadToolchainValue $lockText 'runtime' 'node_path'
    Version = Get-MgReadToolchainValue $lockText 'runtime' 'node_version'
    NpmVersion = Get-MgReadToolchainValue $lockText 'runtime' 'npm_version'
  }
  $harmony = [ordered]@{
    SdkRoot = Get-MgReadToolchainValue $lockText 'harmony' 'ohos_sdk_path'
    ApiLevel = Get-MgReadToolchainValue $lockText 'harmony' 'api_level'
  }
  $rust = [ordered]@{
    Root = Get-MgReadToolchainValue $lockText 'rust' 'root'
    Toolchain = Get-MgReadToolchainValue $lockText 'rust' 'toolchain'
    Targets = [ordered]@{
      arm64 = Get-MgReadToolchainValue $lockText 'rust' 'ohos_arm64_target'
      x64 = Get-MgReadToolchainValue $lockText 'rust' 'ohos_x64_target'
    }
  }
  return [ordered]@{
    LockPath = $lockPath
    Flutter = $flutter
    BuildNode = $buildNode
    RuntimeNode = $runtimeNode
    Harmony = $harmony
    Rust = $rust
  }
}

function Get-MgReadOhosVariant {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('debug', 'release')][string]$BuildMode,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture
  )

  $targetPlatform = if ($Architecture -eq 'arm64') { 'ohos-arm64' } else { 'ohos-x64' }
  $abi = if ($Architecture -eq 'arm64') { 'arm64-v8a' } else { 'x86_64' }
  $nativeName = if ($Architecture -eq 'arm64') { 'flutter_native_arm64_v8a' } else { 'flutter_native_x86_64' }
  $nativeHar = if ($Architecture -eq 'arm64') { "arm64_v8a_$BuildMode.har" } else { "x86_64_$BuildMode.har" }
  $engineDirectory = if ($BuildMode -eq 'debug') { $targetPlatform } else { "$targetPlatform-release" }
  return [ordered]@{
    Id = "$BuildMode-$Architecture"
    BuildMode = $BuildMode
    Architecture = $Architecture
    TargetPlatform = $targetPlatform
    Abi = $abi
    NativePackage = $nativeName
    EmbeddingHar = "flutter_embedding_$BuildMode.har"
    NativeHar = $nativeHar
    EngineDirectory = $engineDirectory
  }
}

function Get-MgReadOhosVariantRoot {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][hashtable]$Variant
  )
  return Join-Path $ProjectRoot ".mgread-build\ohos\$($Variant.Id)"
}

function Assert-MgReadExactNode {
  param(
    [Parameter(Mandatory = $true)][string]$NodeExecutable,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $NodeExecutable -PathType Leaf)) {
    throw "Pinned $Label Node executable is missing: $NodeExecutable"
  }
  $actual = (& $NodeExecutable --version 2>&1 | Out-String).Trim().TrimStart('v')
  if ($actual -ne $ExpectedVersion) {
    throw "Pinned $Label Node version mismatch: expected $ExpectedVersion, got $actual ($NodeExecutable)"
  }
}

function Assert-MgReadExactNpm {
  param(
    [Parameter(Mandatory = $true)][string]$NpmExecutable,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $NpmExecutable -PathType Leaf)) {
    throw "Pinned $Label npm executable is missing: $NpmExecutable"
  }
  $actual = (& $NpmExecutable --version 2>&1 | Out-String).Trim()
  if ($actual -ne $ExpectedVersion) {
    throw "Pinned $Label npm version mismatch: expected $ExpectedVersion, got $actual ($NpmExecutable)"
  }
}

function Assert-MgReadOhosToolchain {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Toolchain,
    [Parameter(Mandatory = $true)][hashtable]$Variant,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
  )

  $flutterBat = Join-Path $Toolchain.Flutter.Root 'bin\flutter.bat'
  $buildNode = Join-Path $Toolchain.BuildNode.Root 'node.exe'
  $buildNpm = Join-Path $Toolchain.BuildNode.Root 'npm.cmd'
  $runtimeNode = Join-Path $Toolchain.RuntimeNode.Root 'node.exe'
  $runtimeNpm = Join-Path $Toolchain.RuntimeNode.Root 'npm.cmd'
  $requiredToolchainPaths = @($flutterBat, $buildNpm, $runtimeNpm)
  foreach ($path in $requiredToolchainPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Pinned OHOS toolchain input is missing: $path"
    }
  }
  Assert-MgReadExactNode $buildNode $Toolchain.BuildNode.Version 'OHOS build'
  Assert-MgReadExactNpm $buildNpm $Toolchain.BuildNode.NpmVersion 'OHOS build'
  Assert-MgReadExactNode $runtimeNode $Toolchain.RuntimeNode.Version 'Runtime'
  Assert-MgReadExactNpm $runtimeNpm $Toolchain.RuntimeNode.NpmVersion 'Runtime'

  $flutterInfo = (& $flutterBat --version --machine 2>$null | ConvertFrom-Json)
  if ($flutterInfo.frameworkVersion -ne $Toolchain.Flutter.Version -or
      -not $flutterInfo.frameworkRevision.StartsWith($Toolchain.Flutter.FrameworkRevision) -or
      -not $flutterInfo.engineRevision.StartsWith($Toolchain.Flutter.EngineRevision) -or
      $flutterInfo.dartSdkVersion -ne $Toolchain.Flutter.DartVersion) {
    throw @"
Pinned Flutter toolchain mismatch.
  expected: $($Toolchain.Flutter.Version), Dart $($Toolchain.Flutter.DartVersion)
  actual:   $($flutterInfo.frameworkVersion), Dart $($flutterInfo.dartSdkVersion)
  path:     $flutterBat
"@
  }

  $engineRoot = Join-Path $Toolchain.Flutter.Root 'bin\cache\artifacts\engine'
  $engineDirectory = Join-Path $engineRoot $Variant.EngineDirectory
  foreach ($har in @($Variant.EmbeddingHar, $Variant.NativeHar)) {
    $harPath = Join-Path $engineDirectory $har
    if (-not (Test-Path -LiteralPath $harPath -PathType Leaf)) {
      throw "Pinned Flutter $($Variant.Id) HAR is missing: $harPath"
    }
  }
  $nodeRoot = Join-Path (Join-Path $ProjectRoot 'packages\mgread_plugin_runtime\ohos\src\main\cpp\node-runtime') $Variant.Architecture
  $nodeSoname = 'libnode.so'
  $nodeSonameFile = Join-Path $nodeRoot 'mgread-node-soname.txt'
  if (Test-Path -LiteralPath $nodeSonameFile -PathType Leaf) {
    $nodeSoname = (Get-Content -LiteralPath $nodeSonameFile -Raw).Trim()
  }
  if ($nodeSoname -notmatch '^libnode\.so(?:\.\d+)*$') {
    throw "Pinned OHOS Node SONAME is invalid: $nodeSoname"
  }
  foreach ($path in @(
      (Join-Path $nodeRoot "lib\$nodeSoname"),
      (Join-Path $nodeRoot 'mgread-node-target.txt'),
      (Join-Path $ProjectRoot 'packages\mgread_plugin_runtime\ohos\src\main\cpp\node-source\src\node.h')
    )) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Pinned OHOS native Runtime input is missing: $path"
    }
  }
  $nodeTarget = (Get-Content -LiteralPath (Join-Path $nodeRoot 'mgread-node-target.txt') -Raw).Trim()
  if ($nodeTarget -ne $Variant.Architecture) {
    throw "OHOS native Node target '$nodeTarget' does not match $($Variant.Architecture)."
  }
}

function Set-MgReadOhosBuildEnvironment {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Toolchain,
    [Parameter(Mandatory = $true)][hashtable]$Variant,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
  )

  $variantRoot = Get-MgReadOhosVariantRoot $ProjectRoot $Variant
  New-Item -ItemType Directory -Force -Path $variantRoot | Out-Null
  $env:MGREAD_OHOS_VARIANT = $Variant.Id
  $env:MGREAD_NODE_ROOT = Join-Path (Join-Path $ProjectRoot 'packages\mgread_plugin_runtime\ohos\src\main\cpp\node-runtime') $Variant.Architecture
  $env:MGREAD_NODE_SOURCE_ROOT = Join-Path $ProjectRoot 'packages\mgread_plugin_runtime\ohos\src\main\cpp\node-source'
  $env:OHOS_SDK_NATIVE = Join-Path $Toolchain.Harmony.SdkRoot 'openharmony\native'
  $env:Path = "$($Toolchain.BuildNode.Root);$(Join-Path $Toolchain.Flutter.Root 'bin');$env:Path"
  return $variantRoot
}

function Set-MgReadOhosNativeBuildProfileArchitecture {
  param(
    [Parameter(Mandatory = $true)][object[]]$ProfileFiles,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture
  )

  $selectedAbi = if ($Architecture -eq 'arm64') { 'arm64-v8a' } else { 'x86_64' }
  $abiArrayPattern = '(?s)"abiFilters"\s*:\s*\[(?<values>.*?)\]'
  foreach ($profileFile in $ProfileFiles) {
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

function Set-MgReadOhosBuildModeMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$PackagesRoot,
    [Parameter(Mandatory = $true)][ValidateSet('debug', 'release')][string]$BuildMode
  )

  $buildModeFiles = @(
    Get-ChildItem -LiteralPath $PackagesRoot -Recurse -File -Filter 'BuildProfile.ets' -ErrorAction SilentlyContinue
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

function Build-MgReadOhosRustRuntime {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Toolchain,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$TargetDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture
  )

  $rustRoot = $Toolchain.Rust.Root
  $cargoExecutable = Join-Path $rustRoot 'cargo\bin\cargo.exe'
  $rustupExecutable = Join-Path $rustRoot 'cargo\bin\rustup.exe'
  $rustToolchainBin = Join-Path $rustRoot "rustup\toolchains\$($Toolchain.Rust.Toolchain)\bin"
  $rustProject = Join-Path $ProjectRoot 'packages\mgread_ohos_native_runtime\native\rust-runtime'
  $rustTargetTriple = $Toolchain.Rust.Targets[$Architecture]
  if ([string]::IsNullOrWhiteSpace($rustTargetTriple)) {
    throw "OHOS Rust target is not pinned for architecture $Architecture."
  }
  $rustTargetEnvironment = $rustTargetTriple.Replace('-', '_')
  $rustTargetEnvironmentUpper = $rustTargetEnvironment.ToUpperInvariant()
  $env:CARGO_TARGET_DIR = $TargetDirectory
  $rustTarget = Join-Path $env:CARGO_TARGET_DIR "$rustTargetTriple\release\libmgread_rust_runtime.so"
  $rustInclude = Join-Path $rustProject 'include'
  $rustLinker = Join-Path $ProjectRoot 'packages\mgread_ohos_native_runtime\native\ohos-clang-linker.cmd'
  $rustCompiler = Join-Path $ProjectRoot 'packages\mgread_ohos_native_runtime\native\ohos-clang-cc.cmd'

  foreach ($requiredPath in @($cargoExecutable, $rustupExecutable, $rustProject, $rustLinker, $rustCompiler, (Join-Path $rustInclude 'mgread_runtime.h'))) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "OHOS Rust runtime build input is missing: $requiredPath"
    }
  }

  $env:CARGO_HOME = Join-Path $rustRoot 'cargo'
  $env:RUSTUP_HOME = Join-Path $rustRoot 'rustup'
  $rustStdDirectory = Join-Path $rustRoot "rustup\toolchains\$($Toolchain.Rust.Toolchain)\lib\rustlib\$rustTargetTriple\lib"
  if (-not (Test-Path -LiteralPath $rustStdDirectory -PathType Container)) {
    & $rustupExecutable target add --toolchain $Toolchain.Rust.Toolchain $rustTargetTriple
    if ($LASTEXITCODE -ne 0) {
      throw "Pinned Rust toolchain could not install OHOS target $rustTargetTriple."
    }
  }
  if (-not (Test-Path -LiteralPath $rustStdDirectory -PathType Container)) {
    throw "Pinned Rust standard library for OHOS target $rustTargetTriple is missing: $rustStdDirectory"
  }

  $env:Path = "$rustRoot\cargo\bin;$rustToolchainBin;$env:Path"
  $env:OHOS_SDK_NATIVE = Join-Path $Toolchain.Harmony.SdkRoot 'openharmony\native'
  $env:MGREAD_OHOS_TARGET_ARCH = $Architecture
  [Environment]::SetEnvironmentVariable("CARGO_TARGET_${rustTargetEnvironmentUpper}_LINKER", $rustLinker, 'Process')
  [Environment]::SetEnvironmentVariable("CC_${rustTargetEnvironment}", $rustCompiler, 'Process')
  [Environment]::SetEnvironmentVariable("AR_${rustTargetEnvironment}", (Join-Path $env:OHOS_SDK_NATIVE 'llvm\bin\llvm-ar.exe'), 'Process')

  Push-Location $rustProject
  try {
    & $cargoExecutable "+$($Toolchain.Rust.Toolchain)" build --locked --release --target $rustTargetTriple
    if ($LASTEXITCODE -ne 0) {
      throw "OHOS $Architecture Rust runtime build failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
  if (-not (Test-Path -LiteralPath $rustTarget -PathType Leaf)) {
    throw "OHOS Rust runtime build completed without producing: $rustTarget"
  }
  return @{ Library = $rustTarget; Include = $rustInclude }
}
