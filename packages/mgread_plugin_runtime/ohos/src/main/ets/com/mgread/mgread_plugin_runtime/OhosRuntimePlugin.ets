import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  EventChannel,
} from '@ohos/flutter_ohos'
import OhosRuntimeProgressStreamHandler from './OhosRuntimeProgressStreamHandler'

/**
 * OHOS Runtime bridge.
 *
 * The bridge is deliberately present even before a verified Node 24.16.0
 * OHOS arm64 binary is available. It gives Dart one stable error envelope and
 * keeps all future VM/process ownership inside this package.
 */
export default class OhosRuntimePlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel
  private progressChannel?: EventChannel

  getUniqueClassName(): string {
    return 'OhosRuntimePlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread_plugin_runtime/ohos')
    this.channel.setMethodCallHandler(this)
    this.progressChannel = new EventChannel(binding.getBinaryMessenger(), 'mgread_plugin_runtime/ohos/progress')
    this.progressChannel.setStreamHandler(new OhosRuntimeProgressStreamHandler())
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
    this.progressChannel?.setStreamHandler(null)
    this.progressChannel = undefined
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'cancelInvocation':
      case 'dispose':
        result.success(null)
        break
      case 'invoke':
        result.error(
          'unsupported',
          'Node 24.16.0 OHOS Runtime host is not bundled for this build.',
          null,
        )
        break
      default:
        result.notImplemented()
        break
    }
  }
}
