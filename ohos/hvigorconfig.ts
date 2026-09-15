import path from 'path'
import { injectNativeModules } from 'flutter-hvigor-plugin';
import { bridgeCrossDrivePlugins } from './flutter_ohos_plugin_bridge';

const nativeProjectPath = __dirname
const flutterProjectPath = path.dirname(nativeProjectPath)

bridgeCrossDrivePlugins()
injectNativeModules(nativeProjectPath, flutterProjectPath)
