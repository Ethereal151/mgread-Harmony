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
$entryBuildProfile = Join-Path $projectRoot 'ohos\entry\build-profile.json5'
$hapDirectory = Join-Path $projectRoot 'build\ohos\hap'
$targetPlatform = "ohos-$Architecture"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "mgread-ohos-release-$PID"
$backupPubspec = Join-Path $temporaryRoot 'mgread_plugin_runtime.pubspec.yaml'
$backupEntryPackage = Join-Path $temporaryRoot 'entry.oh-package.json5'
$backupEntryBuildProfile = Join-Path $temporaryRoot 'entry.build-profile.json5'

if (-not (Test-Path -LiteralPath $runtimePubspec -PathType Leaf)) {
  throw "Runtime pubspec not found: $runtimePubspec"
}
if (-not (Test-Path -LiteralPath $entryPackage -PathType Leaf)) {
  throw "OHOS entry package not found: $entryPackage"
}
if (-not (Test-Path -LiteralPath $entryBuildProfile -PathType Leaf)) {
  throw "OHOS entry build profile not found: $entryBuildProfile"
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
Copy-Item -LiteralPath $runtimePubspec -Destination $backupPubspec -Force
Copy-Item -LiteralPath $entryPackage -Destination $backupEntryPackage -Force
Copy-Item -LiteralPath $entryBuildProfile -Destination $backupEntryBuildProfile -Force

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
  $selectedArchitecturePath = if ($Architecture -eq 'arm64') { 'libs/arm64-v8a/' } else { 'libs/x86_64/' }
  $selectedArchitectureEntries = @($hapEntries | Where-Object { $_ -like "$selectedArchitecturePath*" })
  if ($selectedArchitectureEntries.Count -eq 0) {
    throw "The generated HAP does not contain the requested architecture: $selectedArchitecturePath"
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
  Write-Host ("OHOS $BuildMode HAP: {0} ({1:N2} MB)" -f $hap.FullName, ($hap.Length / 1MB))
} finally {
  Copy-Item -LiteralPath $backupPubspec -Destination $runtimePubspec -Force
  Copy-Item -LiteralPath $backupEntryPackage -Destination $entryPackage -Force
  Copy-Item -LiteralPath $backupEntryBuildProfile -Destination $entryBuildProfile -Force
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Restored temporary OHOS build configuration.'
}
