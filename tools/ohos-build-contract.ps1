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
  foreach ($path in @($flutterBat, $buildNpm, $runtimeNpm)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Pinned OHOS toolchain input is missing: $path"
    }
  }
  Assert-MgReadExactNode $buildNode $Toolchain.BuildNode.Version 'OHOS build'
  Assert-MgReadExactNode $runtimeNode $Toolchain.RuntimeNode.Version 'Runtime'
  Assert-MgReadExactNpm $buildNpm $Toolchain.BuildNode.NpmVersion 'OHOS build'
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
  foreach ($path in @(
      (Join-Path $nodeRoot 'lib\libnode.so'),
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
