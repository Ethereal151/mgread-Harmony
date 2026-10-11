import fs from 'fs'
import path from 'path'
import { spawnSync } from 'child_process'
import { injectNativeModules } from 'flutter-hvigor-plugin';
import { bridgeCrossDrivePlugins } from './flutter_ohos_plugin_bridge';

const nativeProjectPath = __dirname
const flutterProjectPath = path.dirname(nativeProjectPath)

function readLocalProperty(name: string): string | undefined {
  const propertiesPath = path.join(nativeProjectPath, 'local.properties')
  if (!fs.existsSync(propertiesPath)) {
    return undefined
  }
  const prefix = `${name}=`
  const line = fs.readFileSync(propertiesPath, 'utf8')
    .split(/\r?\n/u)
    .find((value) => value.startsWith(prefix))
  return line?.slice(prefix.length).replace(/\\\\/gu, '\\')
}

function readHvigorProperty(name: string): string | undefined {
  const property = process.argv.find((value) => value.startsWith(`${name}=`))
  return property?.slice(name.length + 1)
}

function detectOhosArchitecture(): 'arm64' | 'x64' {
  const explicit = process.env.MGREAD_OHOS_ARCHITECTURE
  if (explicit === 'arm64' || explicit === 'x64') {
    return explicit
  }
  const variant = process.env.MGREAD_OHOS_VARIANT
  if (variant?.endsWith('-arm64')) {
    return 'arm64'
  }
  if (variant?.endsWith('-x64')) {
    return 'x64'
  }

  const moduleName = readHvigorProperty('module')
  const profilePath = moduleName
    ? path.join(flutterProjectPath, moduleName, 'ohos', 'build-profile.json5')
    : path.join(nativeProjectPath, 'entry', 'build-profile.json5')
  if (fs.existsSync(profilePath)) {
    const profile = fs.readFileSync(profilePath, 'utf8')
    const hasArm64 = /arm64-v8a/u.test(profile)
    const hasX64 = /x86_64/u.test(profile)
    if (hasArm64 !== hasX64) {
      return hasArm64 ? 'arm64' : 'x64'
    }
  }
  // Hvigor does not expose `-p module=...` to hvigorconfig.ts. A direct
  // native module invocation therefore has no profile path here; the module
  // currently owns the x86_64 profile. Full Flutter builds always set the
  // variant through the contract before reaching this fallback.
  return 'x64'
}

function applyOhosBuildContract(): void {
  const architecture = detectOhosArchitecture()
  const variant = process.env.MGREAD_OHOS_VARIANT
  const buildMode = variant?.startsWith('release-') ? 'release' : 'debug'
  const contractScript = path.join(flutterProjectPath, 'tools', 'prepare_ohos_hvigor_environment.ps1')
  const powershell = process.env.MGREAD_POWERSHELL ?? 'powershell.exe'
  const result = spawnSync(
    powershell,
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      contractScript,
      '-ProjectRoot',
      flutterProjectPath,
      '-BuildMode',
      buildMode,
      '-Architecture',
      architecture,
    ],
    { encoding: 'utf8' }
  )
  if (result.error || result.status !== 0) {
    const details = (result.stderr || result.stdout || result.error?.message || '').trim()
    throw new Error(`OHOS build contract failed for direct Hvigor (${architecture}): ${details}`)
  }
  let environment: Record<string, string>
  try {
    environment = JSON.parse(result.stdout.trim()) as Record<string, string>
  } catch (error) {
    throw new Error(`OHOS build contract returned invalid environment JSON: ${String(error)}`)
  }
  for (const [name, value] of Object.entries(environment)) {
    if (value) {
      process.env[name] = value
    }
  }
  process.env.MGREAD_OHOS_ARCHITECTURE = architecture
}

const nodeHome = readLocalProperty('nodejs.dir') ?? path.dirname(process.execPath)
const devecoToolsPath = path.dirname(nodeHome)
const sdkHome = readLocalProperty('hwsdk.dir')

// DevEco may export DEVECO_SDK_HOME with the legacy `sdk\\default` suffix.
// The project property is the authoritative SDK root for this checkout and
// must win before Hvigor resolves the HarmonyOS component set.
if (sdkHome) {
  process.env.DEVECO_SDK_HOME = sdkHome
}

applyOhosBuildContract()

// Avoid the recursive DevEco ohpm.bat wrapper when the IDE starts Hvigor by Node.
process.env.MGREAD_OHPM_NODE = path.join(nodeHome, 'node.exe')
process.env.MGREAD_OHPM_CLI = path.join(devecoToolsPath, 'ohpm', 'bin', 'pm-cli.js')
process.env.ohpmBin = path.join(nativeProjectPath, 'tools', 'ohpm-safe.cmd')

bridgeCrossDrivePlugins()
injectNativeModules(nativeProjectPath, flutterProjectPath)
