import path from 'path'
import { injectNativeModules } from 'flutter-hvigor-plugin';
import { bridgeCrossDrivePlugins } from './flutter_ohos_plugin_bridge';

const nativeProjectPath = __dirname
const flutterProjectPath = path.dirname(nativeProjectPath)
const devecoToolsPath = path.dirname(path.dirname(process.execPath))

// Avoid the recursive DevEco ohpm.bat wrapper when the IDE starts Hvigor by Node.
process.env.MGREAD_OHPM_NODE = process.execPath
process.env.MGREAD_OHPM_CLI = path.join(devecoToolsPath, 'ohpm', 'bin', 'pm-cli.js')
process.env.ohpmBin = path.join(nativeProjectPath, 'tools', 'ohpm-safe.cmd')

bridgeCrossDrivePlugins()
injectNativeModules(nativeProjectPath, flutterProjectPath)
