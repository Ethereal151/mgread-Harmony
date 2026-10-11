import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import MgReadOhosMediaPlugin from 'mgread_ohos_media';
import OhosNativeRuntimePlugin from 'mgread_ohos_native_runtime';
import MgReadOhosScannerPlugin from 'mgread_ohos_scanner';
import MgReadOhosSystemPlugin from 'mgread_ohos_system';
import NovelReaderUiPlugin from 'novel_reader_ui';
import ScreenBrightnessOhosPlugin from 'screen_brightness_ohos';
import OhosRuntimePlugin from 'mgread_plugin_runtime';

/**
 * Generated from the OHOS plugin declarations used by this checkout.
 * Keep this file in sync with the plugin list in .flutter-plugins-dependencies.
 */
const TAG = 'GeneratedPluginRegistrant';

export class GeneratedPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine) {
    try {
      flutterEngine.getPlugins()?.add(new MgReadOhosMediaPlugin());
      flutterEngine.getPlugins()?.add(new OhosNativeRuntimePlugin());
      flutterEngine.getPlugins()?.add(new MgReadOhosScannerPlugin());
      flutterEngine.getPlugins()?.add(new MgReadOhosSystemPlugin());
      flutterEngine.getPlugins()?.add(new NovelReaderUiPlugin());
      flutterEngine.getPlugins()?.add(new ScreenBrightnessOhosPlugin());
      flutterEngine.getPlugins()?.add(new OhosRuntimePlugin());
    } catch (e) {
      Log.e(TAG, 'Tried to register plugins with FlutterEngine failed.');
      Log.e(TAG, 'Received exception while registering', e);
    }
  }
}
