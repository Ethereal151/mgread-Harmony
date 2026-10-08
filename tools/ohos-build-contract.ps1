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

function Get-MgReadOhosNodeArtifactRoot {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture
  )

  $configuredRoot = [Environment]::GetEnvironmentVariable('MGREAD_NODE_ARTIFACT_ROOT', 'Process')
  if ([string]::IsNullOrWhiteSpace($configuredRoot)) {
    $configuredRoot = Join-Path $ProjectRoot '.mgread-build\node-artifacts'
  }
  $configuredRoot = [IO.Path]::GetFullPath($configuredRoot)
  if (Test-Path -LiteralPath (Join-Path $configuredRoot 'manifest.json') -PathType Leaf) {
    return $configuredRoot
  }
  return Join-Path $configuredRoot "mgread-ohos-node-26.10.0-$Architecture"
}

function Get-MgReadOhosNodeInputs {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture
  )

  $artifactRoot = Get-MgReadOhosNodeArtifactRoot -ProjectRoot $ProjectRoot -Architecture $Architecture
  $legacyRoot = Join-Path (Join-Path $ProjectRoot 'packages\mgread_plugin_runtime\ohos\src\main\cpp\node-runtime') $Architecture
  $legacySourceRoot = Join-Path $ProjectRoot 'packages\mgread_plugin_runtime\ohos\src\main\cpp\node-source'
  $artifactExists = Test-Path -LiteralPath $artifactRoot -PathType Container
  $manifestExists = Test-Path -LiteralPath (Join-Path $artifactRoot 'manifest.json') -PathType Leaf
  $requireArtifact = [Environment]::GetEnvironmentVariable('MGREAD_NODE_ARTIFACT_REQUIRED', 'Process') -eq 'true'
  if ($artifactExists -and -not $manifestExists) {
    throw "OHOS Node Artifact directory exists without manifest.json: $artifactRoot"
  }
  if ($manifestExists) {
    return [ordered]@{
      Mode = 'artifact'
      RuntimeRoot = $artifactRoot
      SourceRoot = Join-Path $artifactRoot 'node-source'
      ArtifactRoot = $artifactRoot
      ArtifactName = "mgread-ohos-node-26.10.0-$Architecture"
    }
  }
  if ($requireArtifact) {
    throw "OHOS Node Artifact is required but missing: $artifactRoot"
  }
  return [ordered]@{
    Mode = 'legacy'
    RuntimeRoot = $legacyRoot
    SourceRoot = $legacySourceRoot
    ArtifactRoot = $null
    ArtifactName = $null
  }
}

function Assert-MgReadOhosNodeInputs {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Toolchain,
    [Parameter(Mandatory = $true)][hashtable]$Variant,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
  )

  $inputs = Get-MgReadOhosNodeInputs -ProjectRoot $ProjectRoot -Architecture $Variant.Architecture
  $nodeExecutable = Join-Path $Toolchain.BuildNode.Root 'node.exe'
  $artifactVerifier = Join-Path $ProjectRoot 'packages\mg_read_node_runtime\tools\ohos-node-artifact.mjs'
  if ($inputs.Mode -eq 'artifact') {
    if (-not (Test-Path -LiteralPath $artifactVerifier -PathType Leaf)) {
      throw "OHOS Node Artifact verifier is missing: $artifactVerifier"
    }
    $verificationOutput = (& $nodeExecutable $artifactVerifier verify $Variant.Architecture $inputs.ArtifactRoot 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
      throw "OHOS Node Artifact verification failed for $($inputs.ArtifactRoot): $verificationOutput"
    }
    try {
      $verification = $verificationOutput | ConvertFrom-Json
    } catch {
      throw "OHOS Node Artifact verifier returned invalid JSON: $verificationOutput"
    }
    return [ordered]@{
      Mode = $inputs.Mode
      RuntimeRoot = $inputs.RuntimeRoot
      SourceRoot = $inputs.SourceRoot
      ArtifactRoot = $inputs.ArtifactRoot
      ArtifactName = $inputs.ArtifactName
      Soname = $verification.soname
      LibrarySha256 = $verification.librarySha256
      SourceSha256 = $verification.sourceSha256
      SourceFiles = $verification.sourceFiles
      SourceBytes = $verification.sourceBytes
    }
  }

  $sonameFile = Join-Path $inputs.RuntimeRoot 'mgread-node-soname.txt'
  $soname = 'libnode.so'
  if (Test-Path -LiteralPath $sonameFile -PathType Leaf) {
    $soname = (Get-Content -LiteralPath $sonameFile -Raw).Trim()
  }
  foreach ($path in @(
      (Join-Path $inputs.RuntimeRoot "lib\$soname"),
      (Join-Path $inputs.RuntimeRoot 'mgread-node-target.txt'),
      (Join-Path $inputs.RuntimeRoot 'include\node\node_version.h'),
      (Join-Path $inputs.SourceRoot 'src\node.h'),
      (Join-Path $inputs.SourceRoot 'deps\v8\include\include\v8.h')
    )) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Legacy OHOS Node input is missing: $path"
    }
  }
  $target = (Get-Content -LiteralPath (Join-Path $inputs.RuntimeRoot 'mgread-node-target.txt') -Raw).Trim()
  if ($target -ne $Variant.Architecture) {
    throw "Legacy OHOS Node target '$target' does not match $($Variant.Architecture)."
  }
  $metadataPath = Join-Path $inputs.RuntimeRoot 'mgread-node-build.json'
  if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.nodeVersion -ne '26.10.0' -or $metadata.target -ne "openharmony-$($Variant.Architecture)") {
      throw "Legacy OHOS Node metadata does not match Node 26.10.0 $($Variant.Architecture)."
    }
  } else {
    $versionHeader = Get-Content -LiteralPath (Join-Path $inputs.RuntimeRoot 'include\node\node_version.h') -Raw
    if ($versionHeader -notmatch '(?m)^\s*#define\s+NODE_MAJOR_VERSION\s+26\s*$' -or
        $versionHeader -notmatch '(?m)^\s*#define\s+NODE_MINOR_VERSION\s+10\s*$' -or
        $versionHeader -notmatch '(?m)^\s*#define\s+NODE_PATCH_VERSION\s+0\s*$') {
      throw "Legacy OHOS Node headers do not report Node 26.10.0 $($Variant.Architecture)."
    }
  }
  $libraryPath = Join-Path $inputs.RuntimeRoot "lib\$soname"
  return [ordered]@{
    Mode = $inputs.Mode
    RuntimeRoot = $inputs.RuntimeRoot
    SourceRoot = $inputs.SourceRoot
    ArtifactRoot = $null
    ArtifactName = $null
    Soname = $soname
    LibrarySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $libraryPath).Hash
    SourceSha256 = $null
    SourceFiles = $null
    SourceBytes = $null
  }
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
  Assert-MgReadOhosNodeInputs -Toolchain $Toolchain -Variant $Variant -ProjectRoot $ProjectRoot | Out-Null
}

function Set-MgReadOhosBuildEnvironment {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Toolchain,
    [Parameter(Mandatory = $true)][hashtable]$Variant,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
  )

  $variantRoot = Get-MgReadOhosVariantRoot $ProjectRoot $Variant
  $nodeInputs = Assert-MgReadOhosNodeInputs -Toolchain $Toolchain -Variant $Variant -ProjectRoot $ProjectRoot
  New-Item -ItemType Directory -Force -Path $variantRoot | Out-Null
  $env:MGREAD_OHOS_VARIANT = $Variant.Id
  $env:MGREAD_NODE_ROOT = $nodeInputs.RuntimeRoot
  $env:MGREAD_NODE_SOURCE_ROOT = $nodeInputs.SourceRoot
  $env:MGREAD_NODE_INPUT_MODE = $nodeInputs.Mode
  $env:MGREAD_NODE_ARTIFACT_ID = if ($nodeInputs.ArtifactName) { $nodeInputs.ArtifactName } else { 'legacy-repository-input' }
  $env:MGREAD_NODE_LIBRARY_SHA256 = $nodeInputs.LibrarySha256
  $env:MGREAD_NODE_SOURCE_SHA256 = if ($nodeInputs.SourceSha256) { $nodeInputs.SourceSha256 } else { 'unverified-legacy-source' }
  Write-Host "OHOS Node input: $($nodeInputs.Mode) ($($env:MGREAD_NODE_ARTIFACT_ID))"
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

function Build-MgReadOhosAliceSource {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Toolchain,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$TargetDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
  )

  $rustRoot = $Toolchain.Rust.Root
  $cargoExecutable = Join-Path $rustRoot 'cargo\bin\cargo.exe'
  $rustProject = Join-Path $ProjectRoot 'plugins\sources\aisishuwu-native'
  $rustTargetTriple = $Toolchain.Rust.Targets[$Architecture]
  $rustTargetEnvironment = $rustTargetTriple.Replace('-', '_')
  $rustTargetEnvironmentUpper = $rustTargetEnvironment.ToUpperInvariant()
  $rustTarget = Join-Path $TargetDirectory "$rustTargetTriple\release\libaisishuwu_native.so"
  $rustLinker = Join-Path $ProjectRoot 'packages\mgread_ohos_native_runtime\native\ohos-clang-linker.cmd'
  $rustCompiler = Join-Path $ProjectRoot 'packages\mgread_ohos_native_runtime\native\ohos-clang-cc.cmd'
  $ohosSdkNative = Join-Path $Toolchain.Harmony.SdkRoot 'openharmony\native'
  foreach ($requiredPath in @($cargoExecutable, $rustProject, $rustLinker, $rustCompiler, $ohosSdkNative)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      throw "OHOS Alice source build input is missing: $requiredPath"
    }
  }

  $previousTargetDirectory = [Environment]::GetEnvironmentVariable('CARGO_TARGET_DIR', 'Process')
  $previousTargetArchitecture = [Environment]::GetEnvironmentVariable('MGREAD_OHOS_TARGET_ARCH', 'Process')
  $previousRustFlags = [Environment]::GetEnvironmentVariable('RUSTFLAGS', 'Process')
  try {
    $env:CARGO_TARGET_DIR = $TargetDirectory
    $env:OHOS_SDK_NATIVE = $ohosSdkNative
    $env:MGREAD_OHOS_TARGET_ARCH = $Architecture
    if ($Architecture -eq 'arm64') {
      [Environment]::SetEnvironmentVariable('RUSTFLAGS', '-C link-arg=-Wl,-z,max-page-size=16384', 'Process')
    } else {
      [Environment]::SetEnvironmentVariable('RUSTFLAGS', $null, 'Process')
    }
    [Environment]::SetEnvironmentVariable("CARGO_TARGET_${rustTargetEnvironmentUpper}_LINKER", $rustLinker, 'Process')
    [Environment]::SetEnvironmentVariable("CC_${rustTargetEnvironment}", $rustCompiler, 'Process')
    [Environment]::SetEnvironmentVariable("AR_${rustTargetEnvironment}", (Join-Path $ohosSdkNative 'llvm\bin\llvm-ar.exe'), 'Process')
    Push-Location $rustProject
    try {
      & $cargoExecutable "+$($Toolchain.Rust.Toolchain)" build --locked --release --target $rustTargetTriple
      if ($LASTEXITCODE -ne 0) {
        throw "OHOS $Architecture Alice source build failed with exit code $LASTEXITCODE"
      }
    } finally {
      Pop-Location
    }
  } finally {
    [Environment]::SetEnvironmentVariable('CARGO_TARGET_DIR', $previousTargetDirectory, 'Process')
    [Environment]::SetEnvironmentVariable('MGREAD_OHOS_TARGET_ARCH', $previousTargetArchitecture, 'Process')
    [Environment]::SetEnvironmentVariable('RUSTFLAGS', $previousRustFlags, 'Process')
  }
  if (-not (Test-Path -LiteralPath $rustTarget -PathType Leaf)) {
    throw "OHOS Alice source build completed without producing: $rustTarget"
  }
  New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
  $outputPath = Join-Path $OutputDirectory 'libaisishuwu_native.so'
  Copy-Item -LiteralPath $rustTarget -Destination $outputPath -Force
  Write-Host "OHOS $Architecture Alice source: $outputPath"
  return $outputPath
}
