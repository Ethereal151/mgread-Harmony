<#
.SYNOPSIS
校验小说、漫画、音频和视频阅读主链路的冻结基线。

.DESCRIPTION
职责：拒绝冻结范围内的新增、删除和内容变更，确保阅读主链路保持已验证状态。
边界：此脚本只校验清单中的生产源码，不限制测试、文档或其他功能；需要解冻时必须先取得
用户明确授权，再更新清单并重新验证。
#>
[CmdletBinding()]
param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot '..\docs\development\reading-mainline-freeze.json')
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json

function Get-RelativePath {
  param([Parameter(Mandatory)][string]$Path)

  return [IO.Path]::GetRelativePath($repositoryRoot, $Path).Replace('\', '/')
}

function Add-ScopedFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][hashtable]$Files
  )

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $relative = Get-RelativePath $resolved
  if ($relative -eq '..' -or $relative.StartsWith('../', [StringComparison]::Ordinal)) {
    throw "Frozen scope escaped repository: $relative"
  }
  $Files[$relative] = $resolved
}

$scopedFiles = @{}
foreach ($scope in @($manifest.scope)) {
  $scopePath = Join-Path $repositoryRoot ([string]$scope.path)
  if ($scope.kind -eq 'file') {
    if (-not (Test-Path -LiteralPath $scopePath -PathType Leaf)) {
      throw "Frozen file is missing: $($scope.path)"
    }
    Add-ScopedFile -Path $scopePath -Files $scopedFiles
  } elseif ($scope.kind -eq 'directory') {
    if (-not (Test-Path -LiteralPath $scopePath -PathType Container)) {
      throw "Frozen directory is missing: $($scope.path)"
    }
    Get-ChildItem -LiteralPath $scopePath -Recurse -File -Filter '*.dart' |
      ForEach-Object { Add-ScopedFile -Path $_.FullName -Files $scopedFiles }
  } else {
    throw "Unknown frozen scope kind '$($scope.kind)'."
  }
}

$expectedPaths = @($manifest.files.PSObject.Properties.Name | Sort-Object)
$actualPaths = @($scopedFiles.Keys | Sort-Object)
$scopeDifferences = @(Compare-Object -ReferenceObject $expectedPaths -DifferenceObject $actualPaths)
if ($scopeDifferences.Count -gt 0) {
  $summary = $scopeDifferences |
    Select-Object -First 20 |
    ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
  throw "Reading mainline freeze scope changed:`n$($summary -join [Environment]::NewLine)"
}

$hashDifferences = [System.Collections.Generic.List[string]]::new()
$allowCleanHead = $manifest.allowCleanHead -eq $true
foreach ($path in $expectedPaths) {
  $actualHash = (Get-FileHash -LiteralPath $scopedFiles[$path] -Algorithm SHA256).Hash.ToLowerInvariant()
  $descriptor = $manifest.files.PSObject.Properties[$path].Value
  $expectedHashes = if ($descriptor -is [string]) {
    @(([string]$descriptor).ToLowerInvariant())
  } else {
    @(([string]$descriptor.sha256).ToLowerInvariant())
  }
  $matchesSnapshot = $expectedHashes -contains $actualHash
  $matchesCleanHead = $false
  if (-not $matchesSnapshot -and ($allowCleanHead -or ($descriptor -isnot [string] -and $descriptor.allowCleanHead -eq $true))) {
    & git -C $repositoryRoot diff --quiet HEAD -- $path
    $matchesCleanHead = $LASTEXITCODE -eq 0
  }
  if (-not $matchesSnapshot -and -not $matchesCleanHead) {
    $expectedDescription = $expectedHashes -join ', '
    if ($allowCleanHead -or ($descriptor -isnot [string] -and $descriptor.allowCleanHead -eq $true)) {
      $expectedDescription += ', clean HEAD'
    }
    $hashDifferences.Add("$path (expected $expectedDescription, actual $actualHash)")
  }
}
if ($hashDifferences.Count -gt 0) {
  $summary = $hashDifferences | Select-Object -First 20
  throw "Frozen reading mainline files changed:`n$($summary -join [Environment]::NewLine)"
}

Write-Output "Reading mainline freeze passed: $($expectedPaths.Count) production boundary files verified."
