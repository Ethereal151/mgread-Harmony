import {
  Any,
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos'
import common from '@ohos.app.ability.common'
import window from '@ohos.window'
import inputConsumer from '@ohos.multimodalInput.inputConsumer'
import { KeyCode } from '@ohos.multimodalInput.keyCode'
import { KeyEvent } from '@ohos.multimodalInput.keyEvent'

/** Owns reader/video window state for the current OHOS application window. */
export default class NovelReaderUiPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel
  private context?: common.Context
  private activeWindow?: window.Window
  private keepScreenOn: boolean = false
  private immersiveMode: boolean = false
  private volumeKeyPageTurningEnabled: boolean = false
  private readonly volumeKeyHandler = (event: KeyEvent): void => {
    const direction = event.key.code === KeyCode.KEYCODE_VOLUME_UP
      ? 'up'
      : event.key.code === KeyCode.KEYCODE_VOLUME_DOWN
        ? 'down'
        : undefined
    if (direction === undefined) return
    const argumentsMap: Map<string, Object> = new Map<string, Object>()
    argumentsMap.set('direction', direction)
    this.channel?.invokeMethod('volumeKey', argumentsMap)
  }

  getUniqueClassName(): string {
    return 'NovelReaderUiPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'novel_reader_ui/system')
    this.channel.setMethodCallHandler(this)
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context as common.UIAbilityContext
  }

  onDetachedFromAbility(): void {
    this.disableVolumeKeyPageTurning()
    this.context = undefined
    this.activeWindow = undefined
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.disableVolumeKeyPageTurning()
    this.restoreWindow().catch(() => {})
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
    this.context = undefined
    this.activeWindow = undefined
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getCapabilities':
        result.success({ keepScreenOn: true, immersiveMode: true, volumeKeyPageTurning: true })
        break
      case 'setReaderSystemUi':
        this.setReaderSystemUi(call.args as Map<string, Object> | null, result)
        break
      case 'setVideoWindowMode':
        this.setVideoWindowMode(call.args as Map<string, Object> | null, result)
        break
      case 'setVolumeKeyPageTurningEnabled':
        this.setVolumeKeyPageTurningEnabled(call.args as Map<string, Object> | null, result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private setVolumeKeyPageTurningEnabled(
    args: Map<string, Object> | null,
    result: MethodResult,
  ): void {
    const enabled = args?.get('enabled')
    if (typeof enabled !== 'boolean') {
      result.error('invalid_argument', 'enabled must be a boolean.', null)
      return
    }
    try {
      if (enabled) {
        if (!this.volumeKeyPageTurningEnabled) {
          const optionsUp: inputConsumer.KeyPressedConfig = {
            key: KeyCode.KEYCODE_VOLUME_UP,
            action: 1,
            isRepeat: false,
          }
          const optionsDown: inputConsumer.KeyPressedConfig = {
            key: KeyCode.KEYCODE_VOLUME_DOWN,
            action: 1,
            isRepeat: false,
          }
          inputConsumer.on('keyPressed', optionsUp, this.volumeKeyHandler)
          try {
            inputConsumer.on('keyPressed', optionsDown, this.volumeKeyHandler)
          } catch (error) {
            inputConsumer.off('keyPressed', this.volumeKeyHandler)
            throw new Error(this.errorMessage(error))
          }
          this.volumeKeyPageTurningEnabled = true
        }
      } else {
        this.disableVolumeKeyPageTurning()
      }
      result.success(null)
    } catch (error) {
      result.error('volume_key_unavailable', this.errorMessage(error), null)
    }
  }

  private disableVolumeKeyPageTurning(): void {
    if (!this.volumeKeyPageTurningEnabled) return
    try {
      // off() restores HarmonyOS's normal volume adjustment behavior.
      inputConsumer.off('keyPressed', this.volumeKeyHandler)
    } catch (_) {
      // Detach must remain best effort even if the input service is already gone.
    }
    this.volumeKeyPageTurningEnabled = false
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

  private async setVideoWindowMode(
    args: Map<string, Object> | null,
    result: MethodResult,
  ): Promise<void> {
    const fullscreen = args?.get('fullscreen')
    if (typeof fullscreen !== 'boolean') {
      result.error('invalid_argument', 'fullscreen must be a boolean.', null)
      return
    }
    try {
      const target = await this.applicationWindow()
      await target.setPreferredOrientation(
        fullscreen ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT,
      )
      await target.setWindowLayoutFullScreen(fullscreen)
      await target.setWindowSystemBarEnable(fullscreen ? [] : ['status', 'navigation'])
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
