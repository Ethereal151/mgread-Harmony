# MgRead OHOS HAP build entry point.
#
# It narrows the Flutter Runtime asset manifest and entry native architecture
# only during the build, then restores both files even when the build fails.
# Release and debug share this path so neither package gets desktop Runtime
# assets or an unselected architecture.

param(
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'release',
  [ValidateSet('arm64', 'x64')]
  [string]$Architecture = 'arm64',
  [switch]$NoCodesign
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimePubspec = Join-Path $projectRoot 'packages\mgread_plugin_runtime\pubspec.yaml'
$entryPackage = Join-Path $projectRoot 'ohos\entry\oh-package.json5'
$hapDirectory = Join-Path $projectRoot 'build\ohos\hap'
$targetPlatform = "ohos-$Architecture"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "mgread-ohos-release-$PID"
$backupPubspec = Join-Path $temporaryRoot 'mgread_plugin_runtime.pubspec.yaml'
$backupEntryPackage = Join-Path $temporaryRoot 'entry.oh-package.json5'

if (-not (Test-Path -LiteralPath $runtimePubspec -PathType Leaf)) {
  throw "Runtime pubspec not found: $runtimePubspec"
}
if (-not (Test-Path -LiteralPath $entryPackage -PathType Leaf)) {
  throw "OHOS entry package not found: $entryPackage"
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
Copy-Item -LiteralPath $runtimePubspec -Destination $backupPubspec -Force
Copy-Item -LiteralPath $entryPackage -Destination $backupEntryPackage -Force

try {
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
  $unselectedArchitecture = 'arm64_v8a'
  if ($Architecture -eq 'arm64') {
    $unselectedArchitecture = 'x86_64'
  }
  $entryDependencyPattern = '(?m)^\s*"flutter_native_' + $unselectedArchitecture + '":.*\r?\n'
  $updatedEntry = [regex]::Replace($entrySource, $entryDependencyPattern, '', 1)
  if ($updatedEntry -eq $entrySource) {
    throw "flutter_native_$unselectedArchitecture dependency was not found; stopped to avoid a dual-architecture HAP."
  }
  Set-Content -LiteralPath $entryPackage -Value $updatedEntry -Encoding utf8
  Write-Host "OHOS $targetPlatform $BuildMode uses a temporary OHOS-only Runtime and single-architecture configuration."

  $flutterArguments = 'build', 'hap', "--$BuildMode", '--target-platform', $targetPlatform, '--no-pub'
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
  $unexpectedArchitecturePath = "libs/$unselectedArchitecture/"
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
  Copy-Item -LiteralPath $backupPubspec -Destination $runtimePubspec -Force
  Copy-Item -LiteralPath $backupEntryPackage -Destination $entryPackage -Force
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Restored temporary OHOS build configuration.'
}
