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

/**
 * Owns reader/video window state for the current OHOS application window.
 * All modes use edge-to-edge layout; Flutter SafeArea owns content avoidance.
 * Serialize asynchronous window calls so a late page restore cannot undo a
 * newer immersive request. Page styles only update the cache while immersed.
 */
export default class NovelReaderUiPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel
  private context?: common.Context
  private activeWindow?: window.Window
  private keepScreenOn: boolean = false
  private immersiveMode: boolean = false
  private applicationStatusBarColor: string = '#FDFBFA'
  private applicationNavigationBarColor: string = '#FDFBFA'
  private applicationStatusBarContentColor: string = '#201C18'
  private applicationNavigationBarContentColor: string = '#201C18'
  private mediaSystemUiOwned: boolean = false
  private systemUiRequestGeneration: number = 0
  private windowOperations: Promise<void> = Promise.resolve()
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
        this.enqueueWindowOperation(() => this.setReaderSystemUi(call.args as Map<string, Object> | null, result))
        break
      case 'setVideoWindowMode':
        this.enqueueWindowOperation(() => this.setVideoWindowMode(call.args as Map<string, Object> | null, result))
        break
      case 'setApplicationSystemUiStyle':
        this.enqueueWindowOperation(() => this.setApplicationSystemUiStyle(call.args as Map<string, Object> | null, result))
        break
      case 'restoreApplicationSystemUi':
        this.enqueueWindowOperation(() => this.restoreApplicationSystemUi(result))
        break
      case 'setVideoKeepScreenOn':
        this.enqueueWindowOperation(() => this.setVideoKeepScreenOn(call.args as Map<string, Object> | null, result))
        break
      case 'setVolumeKeyPageTurningEnabled':
        this.setVolumeKeyPageTurningEnabled(call.args as Map<string, Object> | null, result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private enqueueWindowOperation(operation: () => Promise<void>): void {
    this.windowOperations = this.windowOperations.then(operation, operation)
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
      // Audio playback asks this method to keep the screen awake while the
      // media presentation still owns the system bars. Do not interpret that
      // request as a media teardown; the explicit restore method below is the
      // only operation that releases media ownership.
      const preserveMediaBars = !immersive && this.mediaSystemUiOwned
      const generation = preserveMediaBars
        ? this.systemUiRequestGeneration
        : ++this.systemUiRequestGeneration
      const target = await this.applicationWindow()
      await target.setWindowKeepScreenOn(keep)
      if (preserveMediaBars) {
        this.keepScreenOn = keep
        this.immersiveMode = immersive
        result.success(null)
        return
      }
      await target.setWindowLayoutFullScreen(true)
      if (immersive) {
        await target.setWindowSystemBarEnable([])
      } else {
        if (generation !== this.systemUiRequestGeneration) {
          result.success(null)
          return
        }
        await target.setWindowSystemBarEnable(['status', 'navigation'])
        // Reader palettes own icon contrast through AnnotatedRegion. Keep
        // backgrounds transparent instead of painting the cached app theme
        // over the reader's paper/night surface.
        if (generation !== this.systemUiRequestGeneration) {
          result.success(null)
          return
        }
        await target.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
        })
        if (generation !== this.systemUiRequestGeneration) {
          result.success(null)
          return
        }
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
      const generation = ++this.systemUiRequestGeneration
      this.mediaSystemUiOwned = true
      const target = await this.applicationWindow()
      await target.setPreferredOrientation(
        fullscreen ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT,
      )
      await target.setWindowLayoutFullScreen(true)
      if (generation !== this.systemUiRequestGeneration) {
        result.success(null)
        return
      }
      if (fullscreen) {
        await target.setWindowSystemBarEnable([])
        await target.setWindowSystemBarProperties({
          statusBarColor: '#000000',
          navigationBarColor: '#000000',
          statusBarContentColor: '#FFFFFF',
          navigationBarContentColor: '#FFFFFF',
        })
      } else {
        // Portrait media owns the full viewport, but Flutter paints the
        // preparation/player surface beneath both system bars. Keeping both
        // bars visible and transparent prevents a device-default white or
        // stale black gesture area from leaking through.
        await target.setWindowSystemBarEnable(['status', 'navigation'])
        await target.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: '#FFFFFF',
          navigationBarContentColor: '#FFFFFF',
        })
      }
      result.success(null)
    } catch (error) {
      result.error('operation_failed', this.errorMessage(error), null)
    }
  }

  private async setApplicationSystemUiStyle(
    args: Map<string, Object> | null,
    result: MethodResult,
  ): Promise<void> {
    const statusBarColor = args?.get('statusBarColor')
    const navigationBarColor = args?.get('navigationBarColor')
    const statusBarContentColor = args?.get('statusBarContentColor')
    const navigationBarContentColor = args?.get('navigationBarContentColor')
    if (
      typeof statusBarColor !== 'string' ||
      typeof navigationBarColor !== 'string' ||
      typeof statusBarContentColor !== 'string' ||
      typeof navigationBarContentColor !== 'string'
    ) {
      result.error('invalid_argument', 'system bar colors must be strings.', null)
      return
    }
    try {
      this.applicationStatusBarColor = statusBarColor
      this.applicationNavigationBarColor = navigationBarColor
      this.applicationStatusBarContentColor = statusBarContentColor
      this.applicationNavigationBarContentColor = navigationBarContentColor
      if (this.mediaSystemUiOwned || this.immersiveMode) {
        // The page remains mounted below the player during the transition.
        // Cache its colors, but never reveal bars hidden by the active reader
        // or overwrite media-owned bars.
        result.success(null)
        return
      }
      const generation = ++this.systemUiRequestGeneration
      const target = await this.applicationWindow()
      await target.setWindowSystemBarEnable(['status', 'navigation'])
      if (generation !== this.systemUiRequestGeneration) {
        result.success(null)
        return
      }
      await target.setWindowSystemBarProperties({
        statusBarColor: statusBarColor,
        navigationBarColor: navigationBarColor,
        statusBarContentColor: statusBarContentColor,
        navigationBarContentColor: navigationBarContentColor,
      })
      if (generation !== this.systemUiRequestGeneration) {
        result.success(null)
        return
      }
      await target.setWindowLayoutFullScreen(true)
      result.success(null)
    } catch (error) {
      result.error('operation_failed', this.errorMessage(error), null)
    }
  }

  private async restoreApplicationSystemUi(result: MethodResult): Promise<void> {
    try {
      const generation = ++this.systemUiRequestGeneration
      this.mediaSystemUiOwned = false
      const target = await this.applicationWindow()
      await target.setWindowKeepScreenOn(false)
      await target.setWindowSystemBarEnable(['status', 'navigation'])
      if (generation !== this.systemUiRequestGeneration) {
        result.success(null)
        return
      }
      await target.setWindowSystemBarProperties({
        statusBarColor: this.applicationStatusBarColor,
        navigationBarColor: this.applicationNavigationBarColor,
        statusBarContentColor: this.applicationStatusBarContentColor,
        navigationBarContentColor: this.applicationNavigationBarContentColor,
      })
      if (generation !== this.systemUiRequestGeneration) {
        result.success(null)
        return
      }
      await target.setWindowLayoutFullScreen(true)
      this.keepScreenOn = false
      this.immersiveMode = false
      result.success(null)
    } catch (error) {
      result.error('operation_failed', this.errorMessage(error), null)
    }
  }

  private async setVideoKeepScreenOn(
    args: Map<string, Object> | null,
    result: MethodResult,
  ): Promise<void> {
    const enabled = args?.get('enabled')
    if (typeof enabled !== 'boolean') {
      result.error('invalid_argument', 'enabled must be a boolean.', null)
      return
    }
    try {
      const target = await this.applicationWindow()
      await target.setWindowKeepScreenOn(enabled)
      this.keepScreenOn = enabled
      result.success(null)
    } catch (error) {
      result.error('operation_failed', this.errorMessage(error), null)
    }
  }

  private async restoreWindow(): Promise<void> {
    const target = this.activeWindow
    if (target === undefined) return
    ++this.systemUiRequestGeneration
    this.mediaSystemUiOwned = false
    await target.setWindowKeepScreenOn(false)
    await target.setWindowSystemBarEnable(['status', 'navigation'])
    await target.setWindowSystemBarProperties({
      statusBarColor: this.applicationStatusBarColor,
      navigationBarColor: this.applicationNavigationBarColor,
      statusBarContentColor: this.applicationStatusBarContentColor,
      navigationBarContentColor: this.applicationNavigationBarContentColor,
    })
    await target.setWindowLayoutFullScreen(true)
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
