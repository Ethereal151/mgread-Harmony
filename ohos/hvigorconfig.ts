import fs from 'fs'
import path from 'path'
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

const nodeHome = readLocalProperty('nodejs.dir') ?? path.dirname(process.execPath)
const devecoToolsPath = path.dirname(nodeHome)
const sdkHome = readLocalProperty('hwsdk.dir')

// DevEco may export DEVECO_SDK_HOME with the legacy `sdk\\default` suffix.
// The project property is the authoritative SDK root for this checkout and
// must win before Hvigor resolves the HarmonyOS component set.
if (sdkHome) {
  process.env.DEVECO_SDK_HOME = sdkHome
}

// Avoid the recursive DevEco ohpm.bat wrapper when the IDE starts Hvigor by Node.
process.env.MGREAD_OHPM_NODE = path.join(nodeHome, 'node.exe')
process.env.MGREAD_OHPM_CLI = path.join(devecoToolsPath, 'ohpm', 'bin', 'pm-cli.js')
process.env.ohpmBin = path.join(nativeProjectPath, 'tools', 'ohpm-safe.cmd')

bridgeCrossDrivePlugins()
injectNativeModules(nativeProjectPath, flutterProjectPath)
