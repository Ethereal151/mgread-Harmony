import {
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos'
import common from '@ohos.app.ability.common'
import window from '@ohos.window'

/** Owns reader/video window state for the current OHOS application window. */
export default class NovelReaderUiPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel
  private context?: common.Context
  private activeWindow?: window.Window
  private keepScreenOn: boolean = false
  private immersiveMode: boolean = false

  getUniqueClassName(): string {
    return 'NovelReaderUiPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext()
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'novel_reader_ui/system')
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.restoreWindow().catch(() => {})
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
    this.context = undefined
    this.activeWindow = undefined
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getCapabilities':
        result.success({ keepScreenOn: true, immersiveMode: true })
        break
      case 'setReaderSystemUi':
        this.setReaderSystemUi(call.args as Map<string, Object> | null, result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private async setReaderSystemUi(
    args: Map<string, Object> | null,
    result: MethodResult,
  ): Promise<void> {
    const keep = args?.get('keepScreenOn')
    const immersive = args?.get('immersiveMode')
    if (typeof keep !== 'boolean' || typeof immersive !== 'boolean') {
      result.error('invalid_argument', 'keepScreenOn and immersiveMode must be booleans.', null)
      return
    }
    try {
      const target = await this.applicationWindow()
      await target.setWindowKeepScreenOn(keep)
      if (immersive) {
        await target.setWindowSystemBarEnable([])
      } else {
        await target.setWindowSystemBarEnable(['status', 'navigation'])
      }
      this.keepScreenOn = keep
      this.immersiveMode = immersive
      result.success(null)
    } catch (error) {
      result.error('operation_failed', this.errorMessage(error), null)
    }
  }

  private async restoreWindow(): Promise<void> {
    if (this.activeWindow === undefined) return
    await this.activeWindow.setWindowKeepScreenOn(false)
    await this.activeWindow.setWindowSystemBarEnable(['status', 'navigation'])
    this.keepScreenOn = false
    this.immersiveMode = false
  }

  private async applicationWindow(): Promise<window.Window> {
    if (this.activeWindow !== undefined) return this.activeWindow
    if (this.context === undefined) throw new Error('The OHOS application context is not ready.')
    this.activeWindow = await window.getLastWindow(this.context)
    return this.activeWindow
  }

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }
}
