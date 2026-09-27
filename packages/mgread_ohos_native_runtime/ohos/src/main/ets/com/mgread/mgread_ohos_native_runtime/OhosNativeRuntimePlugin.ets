import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos'
import nativeRuntime from 'libmgread_ohos_native_runtime.so'

/** Explicit test/rollout bridge; the application keeps Node Runtime as default. */
export default class OhosNativeRuntimePlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel

  getUniqueClassName(): string {
    return 'OhosNativeRuntimePlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread_ohos_native_runtime')
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
    nativeRuntime.dispose()
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = call.args as Map<string, Object> | null
    switch (call.method) {
      case 'version':
        result.success(nativeRuntime.version())
        break
      case 'create':
        result.success(nativeRuntime.create(String(args?.get('configJson') ?? '')))
        break
      case 'start':
        result.success(nativeRuntime.start())
        break
      case 'invoke':
        nativeRuntime.invoke(String(args?.get('requestJson') ?? ''))
          .then((response: string): void => result.success(response))
          .catch((error: Object): void => result.error('native_runtime_invoke_failed', String(error), null))
        break
      case 'lastError':
        result.success(nativeRuntime.lastError())
        break
      case 'cancel':
        result.success(nativeRuntime.cancel(String(args?.get('requestId') ?? '')))
        break
      case 'stop':
        result.success(nativeRuntime.stop())
        break
      case 'restart':
        result.success(nativeRuntime.restart())
        break
      case 'dispose':
        nativeRuntime.dispose()
        result.success(null)
        break
      default:
        result.notImplemented()
        break
    }
  }
}
