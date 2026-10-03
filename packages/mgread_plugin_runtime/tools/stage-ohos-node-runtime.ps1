param(
  [string]$Distro = 'Ubuntu-24.04',
  [string]$BuildRoot = '\\wsl.localhost\Ubuntu-24.04\root\mgread-node-ohos-build\node-v26.10.0-openharmony-arm64',
  [string]$SourceRoot = '\\wsl.localhost\Ubuntu-24.04\root\mgread-node-ohos-build\node-v26.10.0',
  [ValidateSet('arm64', 'x64')]
  [string]$RuntimeSubdirectory = ''
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$nodeDestination = Join-Path $packageRoot 'ohos\src\main\cpp\node-runtime'
if ($RuntimeSubdirectory) {
  $nodeDestination = Join-Path $nodeDestination $RuntimeSubdirectory
}
$sourceDestination = Join-Path $packageRoot 'ohos\src\main\cpp\node-source'
$nodeLibrary = Join-Path $BuildRoot 'lib\libnode.so'
$versionedNodeLibrary = Join-Path $BuildRoot 'lib\libnode.so.147'
$nodeHeaders = Join-Path $BuildRoot 'include\node'
$nodeSourceHeader = Join-Path $SourceRoot 'src\node.h'
$v8Headers = Join-Path $SourceRoot 'deps\v8\include'
$sourceLocationCompat = Join-Path $packageRoot '..\mg_read_node_runtime\tools\ohos-compat\source_location'
$buildMetadata = Join-Path $BuildRoot 'mgread-node-build.json'

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
if (-not (Test-Path -LiteralPath $sourceLocationCompat -PathType Leaf)) {
  throw "OHOS source_location compatibility header not found: $sourceLocationCompat"
}
$nodeTarget = $null
if (Test-Path -LiteralPath $buildMetadata -PathType Leaf) {
  $metadata = Get-Content -LiteralPath $buildMetadata -Raw | ConvertFrom-Json
  if ($metadata.target -match '^openharmony-(arm64|x64)$') {
    $nodeTarget = $Matches[1]
  }
}
if (-not $nodeTarget) {
  $buildName = Split-Path -Leaf $BuildRoot
  if ($buildName -match 'openharmony-(arm64|x64)$') {
    $nodeTarget = $Matches[1]
  } else {
    throw "Unable to determine the OpenHarmony target ABI from $BuildRoot"
  }
}

New-Item -ItemType Directory -Force -Path $nodeDestination, $sourceDestination | Out-Null
$nodeLibraryDestination = Join-Path $nodeDestination 'lib'
New-Item -ItemType Directory -Force -Path $nodeLibraryDestination | Out-Null
$nodeLibraryFile = Join-Path $nodeLibraryDestination 'libnode.so'
Copy-Item -LiteralPath $nodeLibrary -Destination $nodeLibraryFile -Force

# The shared Node build records the ABI-suffixed SONAME libnode.so.147 while
# hvigor only packs libraries whose file name ends in .so. Normalize the SONAME
# so the host's DT_NEEDED matches the packaged libnode.so.
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  throw "Python is required to normalize the staged Node SONAME."
}
& $python.Source (Join-Path $PSScriptRoot 'set-elf-soname.py') $nodeLibraryFile 'libnode.so'
if ($LASTEXITCODE -ne 0) {
  throw "Failed to normalize the staged Node SONAME."
}
Copy-Item -LiteralPath $nodeHeaders -Destination (Join-Path $nodeDestination 'include') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $SourceRoot 'src') -Destination $sourceDestination -Recurse -Force
New-Item -ItemType Directory -Force -Path (Join-Path $sourceDestination 'deps\v8') | Out-Null
Copy-Item -LiteralPath $v8Headers -Destination (Join-Path $sourceDestination 'deps\v8\include') -Recurse -Force
Copy-Item -LiteralPath $sourceLocationCompat -Destination (Join-Path $sourceDestination 'source_location') -Force
Set-Content -LiteralPath (Join-Path $nodeDestination 'mgread-node-target.txt') -Value $nodeTarget -NoNewline -Encoding ascii

Write-Host "Staged Node 26.10.0 OpenHarmony $nodeTarget runtime into $nodeDestination"
