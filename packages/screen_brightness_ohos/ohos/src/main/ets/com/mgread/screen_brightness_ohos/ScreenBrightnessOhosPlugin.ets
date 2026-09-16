import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos'

/**
 * Safe fallback for OHOS, where MgRead does not expose brightness controls.
 *
 * The upstream plugin touches an OHOS settings Context during engine plugin
 * registration, before an Ability binding exists. Keeping this bridge
 * side-effect free prevents a startup assertion and preserves the federated
 * Dart API for callers that probe optional capabilities.
 */
export default class ScreenBrightnessOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel

  getUniqueClassName(): string {
    return 'ScreenBrightnessOhosPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'github.com/aaassseee/screen_brightness')
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getSystemScreenBrightness':
      case 'getApplicationScreenBrightness':
        result.success(1.0)
        break
      case 'setSystemScreenBrightness':
      case 'setApplicationScreenBrightness':
      case 'resetApplicationScreenBrightness':
      case 'setAutoReset':
      case 'setAnimate':
        result.success(null)
        break
      case 'hasApplicationScreenBrightnessChanged':
        result.success(false)
        break
      case 'isAutoReset':
      case 'isAnimate':
        result.success(true)
        break
      case 'canChangeSystemBrightness':
        result.success(false)
        break
      default:
        result.notImplemented()
        break
    }
  }
}
