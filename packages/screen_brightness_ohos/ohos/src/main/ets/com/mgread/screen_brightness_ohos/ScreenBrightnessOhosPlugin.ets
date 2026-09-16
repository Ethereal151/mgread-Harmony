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

/**
 * Application-scoped brightness adapter for OHOS.
 *
 * OHOS exposes brightness at the window level. The adapter deliberately keeps
 * system brightness methods unavailable because changing the global setting
 * requires a different privileged contract; video only needs the application
 * window override.
 */
export default class ScreenBrightnessOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel?: MethodChannel
  private context?: common.Context
  private activeWindow?: window.Window
  private applicationBrightnessChanged: boolean = false
  private autoReset: boolean = true
  private animate: boolean = true

  getUniqueClassName(): string {
    return 'ScreenBrightnessOhosPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext()
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'github.com/aaassseee/screen_brightness')
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.applicationBrightnessChanged && this.autoReset && this.activeWindow !== undefined) {
      this.activeWindow.setWindowBrightness(-1.0).catch(() => {})
    }
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
    this.context = undefined
    this.activeWindow = undefined
    this.applicationBrightnessChanged = false
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = call.args as Record<string, Any> | null
    switch (call.method) {
      case 'getApplicationScreenBrightness':
        this.run(result, async (): Promise<number> => {
          const brightness = (await this.applicationWindow()).getWindowProperties().brightness
          if (brightness < 0) {
            throw new Error('OHOS is following system brightness; the global value is not exposed to this app.')
          }
          return brightness
        })
        break
      case 'setApplicationScreenBrightness':
        this.run(result, async (): Promise<void> => {
          const brightness = args?.['brightness'] as number | undefined
          if (brightness === undefined || brightness < 0 || brightness > 1) {
            throw new Error('Application brightness must be between 0.0 and 1.0.')
          }
          await (await this.applicationWindow()).setWindowBrightness(brightness)
          this.applicationBrightnessChanged = true
        })
        break
      case 'resetApplicationScreenBrightness':
        this.run(result, async (): Promise<void> => {
          await (await this.applicationWindow()).setWindowBrightness(-1.0)
          this.applicationBrightnessChanged = false
        })
        break
      case 'hasApplicationScreenBrightnessChanged':
        result.success(this.applicationBrightnessChanged)
        break
      case 'isAutoReset':
        result.success(this.autoReset)
        break
      case 'setAutoReset':
        this.autoReset = (args?.['isAutoReset'] as boolean | undefined) ?? true
        result.success(null)
        break
      case 'isAnimate':
        result.success(this.animate)
        break
      case 'setAnimate':
        this.animate = (args?.['isAnimate'] as boolean | undefined) ?? true
        result.success(null)
        break
      case 'getSystemScreenBrightness':
      case 'setSystemScreenBrightness':
      case 'canChangeSystemBrightness':
        result.error('unsupported', 'OHOS exposes application window brightness only.', null)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private async applicationWindow(): Promise<window.Window> {
    if (this.activeWindow === undefined) {
      if (this.context === undefined) {
        throw new Error('The OHOS application context is not ready.')
      }
      this.activeWindow = await window.getLastWindow(this.context)
    }
    return this.activeWindow
  }

  private run<T>(result: MethodResult, operation: () => Promise<T>): void {
    operation().then((value: T): void => result.success(value)).catch((error: Object): void => {
      result.error('operation_failed', this.errorMessage(error), null)
    })
  }

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }
}
