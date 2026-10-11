# Emit the validated OHOS environment consumed by direct Hvigor invocations.
# The project build scripts continue to own the contract; this adapter only
# exposes the same selection and verification to hvigorconfig.ts.

param(
  [Parameter(Mandatory = $true)][string]$ProjectRoot,
  [Parameter(Mandatory = $true)][ValidateSet('debug', 'release')][string]$BuildMode,
  [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ohos-build-contract.ps1')

$variant = Get-MgReadOhosVariant -BuildMode $BuildMode -Architecture $Architecture
$toolchain = Get-MgReadOhosToolchain -ProjectRoot $ProjectRoot
Assert-MgReadOhosToolchain `
  -Toolchain $toolchain `
  -Variant $variant `
  -ProjectRoot $ProjectRoot
$nodeInputs = Assert-MgReadOhosNodeInputs `
  -Toolchain $toolchain `
  -Variant $variant `
  -ProjectRoot $ProjectRoot

[ordered]@{
  MGREAD_OHOS_VARIANT = $variant.Id
  MGREAD_NODE_ROOT = $nodeInputs.RuntimeRoot
  MGREAD_NODE_SOURCE_ROOT = $nodeInputs.SourceRoot
  MGREAD_NODE_INPUT_MODE = $nodeInputs.Mode
  MGREAD_NODE_ARTIFACT_ID = if ($nodeInputs.ArtifactName) { $nodeInputs.ArtifactName } else { 'legacy-repository-input' }
  MGREAD_NODE_LIBRARY_SHA256 = $nodeInputs.LibrarySha256
  MGREAD_NODE_SOURCE_SHA256 = if ($nodeInputs.SourceSha256) { $nodeInputs.SourceSha256 } else { 'unverified-legacy-source' }
  OHOS_SDK_NATIVE = Join-Path $toolchain.Harmony.SdkRoot 'openharmony\native'
  BUILD_NODE_ROOT = $toolchain.BuildNode.Root
  FLUTTER_ROOT = $toolchain.Flutter.Root
} | ConvertTo-Json -Compress
