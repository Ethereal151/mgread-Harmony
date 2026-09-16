param(
  [string]$Distro = 'Ubuntu-24.04',
  [string]$BuildRoot = '\\wsl.localhost\Ubuntu-24.04\root\mgread-node-ohos-build\node-v24.16.0-openharmony-arm64',
  [string]$SourceRoot = '\\wsl.localhost\Ubuntu-24.04\root\mgread-node-ohos-build\node-v24.16.0'
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$nodeDestination = Join-Path $packageRoot 'ohos\src\main\cpp\node-runtime'
$sourceDestination = Join-Path $packageRoot 'ohos\src\main\cpp\node-source'
$nodeLibrary = Join-Path $BuildRoot 'lib\libnode.so'
$versionedNodeLibrary = Join-Path $BuildRoot 'lib\libnode.so.137'
$nodeHeaders = Join-Path $BuildRoot 'include\node'
$nodeSourceHeader = Join-Path $SourceRoot 'src\node.h'
$v8Headers = Join-Path $SourceRoot 'deps\v8\include'

if (-not (Test-Path -LiteralPath $nodeLibrary -PathType Leaf)) {
  if (Test-Path -LiteralPath $versionedNodeLibrary -PathType Leaf) {
    $nodeLibrary = $versionedNodeLibrary
  } else {
    throw "Node shared library not found: $nodeLibrary or $versionedNodeLibrary"
  }
}
if (-not (Test-Path -LiteralPath $nodeHeaders -PathType Container)) {
  throw "Node headers not found: $nodeHeaders"
}
if (-not (Test-Path -LiteralPath $nodeSourceHeader -PathType Leaf)) {
  throw "Node source headers not found: $nodeSourceHeader"
}
if (-not (Test-Path -LiteralPath $v8Headers -PathType Container)) {
  throw "V8 headers not found: $v8Headers"
}

New-Item -ItemType Directory -Force -Path $nodeDestination, $sourceDestination | Out-Null
$nodeLibraryDestination = Join-Path $nodeDestination 'lib'
New-Item -ItemType Directory -Force -Path $nodeLibraryDestination | Out-Null
Copy-Item -LiteralPath $nodeLibrary -Destination (Join-Path $nodeLibraryDestination 'libnode.so') -Force
Copy-Item -LiteralPath $nodeHeaders -Destination (Join-Path $nodeDestination 'include') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $SourceRoot 'src') -Destination $sourceDestination -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $sourceDestination 'deps\v8') | Out-Null
Copy-Item -LiteralPath $v8Headers -Destination (Join-Path $sourceDestination 'deps\v8\include') -Recurse -Force

Write-Host "Staged Node 24.16.0 OpenHarmony arm64 runtime into $nodeDestination"
