# Run an OHOS integration test with an architecture-specific temporary project
# configuration. Flutter's OHOS test runner does not expose --target-platform,
# so the selected native HAR and HAP ABI must be selected before it starts.

param(
  [Parameter(Mandatory = $true)]
  [string]$TestPath,
  [string]$DeviceId = '127.0.0.1:5555',
  [ValidateSet('arm64', 'x64')]
  [string]$Architecture = 'arm64',
  [string[]]$DartDefine = @()
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$entryPackage = Join-Path $projectRoot 'ohos\entry\oh-package.json5'
$entryBuildProfile = Join-Path $projectRoot 'ohos\entry\build-profile.json5'
$entryNativeLibraries = Join-Path $projectRoot 'ohos\entry\libs'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "mgread-ohos-integration-$PID"
$backupEntryPackage = Join-Path $temporaryRoot 'entry.oh-package.json5'
$backupEntryBuildProfile = Join-Path $temporaryRoot 'entry.build-profile.json5'
$backupEntryNativeLibraries = Join-Path $temporaryRoot 'libs'

if (-not (Test-Path -LiteralPath $entryPackage -PathType Leaf)) {
  throw "OHOS entry package not found: $entryPackage"
}
if (-not (Test-Path -LiteralPath $entryBuildProfile -PathType Leaf)) {
  throw "OHOS entry build profile not found: $entryBuildProfile"
}
if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) {
  throw "Integration test not found: $TestPath"
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
Copy-Item -LiteralPath $entryPackage -Destination $backupEntryPackage -Force
Copy-Item -LiteralPath $entryBuildProfile -Destination $backupEntryBuildProfile -Force
if (Test-Path -LiteralPath $entryNativeLibraries -PathType Container) {
  Copy-Item -LiteralPath $entryNativeLibraries -Destination $backupEntryNativeLibraries -Recurse -Force
}

try {
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

  Write-Host "Running OHOS $Architecture integration test on ${DeviceId}: $TestPath"
  $flutterArguments = @('test', $TestPath, '-d', $DeviceId, '--no-pub')
  foreach ($define in $DartDefine) {
    $flutterArguments += "--dart-define=$define"
  }
  & flutter @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter integration test failed with exit code $LASTEXITCODE"
  }
} finally {
  Copy-Item -LiteralPath $backupEntryPackage -Destination $entryPackage -Force
  Copy-Item -LiteralPath $backupEntryBuildProfile -Destination $entryBuildProfile -Force
  if (Test-Path -LiteralPath $backupEntryNativeLibraries -PathType Container) {
    if (Test-Path -LiteralPath $entryNativeLibraries -PathType Container) {
      Remove-Item -LiteralPath $entryNativeLibraries -Recurse -Force
    }
    Copy-Item -LiteralPath $backupEntryNativeLibraries -Destination $entryNativeLibraries -Recurse -Force
  }
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Restored temporary OHOS integration-test configuration.'
}
