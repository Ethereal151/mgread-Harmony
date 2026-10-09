import {
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
import fs from '@ohos.file.fs'
import { picker } from '@kit.CoreFileKit'
import nativeRuntime from 'libmgread_ohos_native_runtime.so'

/** Explicit test/rollout bridge; the application keeps Node Runtime as default. */
export default class OhosNativeRuntimePlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel
  private context?: common.UIAbilityContext

  getUniqueClassName(): string {
    return 'OhosNativeRuntimePlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread_ohos_native_runtime')
    this.channel.setMethodCallHandler(this)
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context as common.UIAbilityContext
  }

  onDetachedFromAbility(): void {
    this.context = undefined
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.channel = undefined
    this.context = undefined
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
      case 'hostStart':
        try {
          result.success(nativeRuntime.hostStart(
            `${this.context?.filesDir ?? ''}/mgread-native-runtime`,
            String(args?.get('token') ?? ''),
            this.context?.applicationInfo.nativeLibraryPath ?? '',
            Boolean(args?.get('testMode') ?? false),
          ))
        } catch (error) {
          result.error('native_runtime_start_failed', String(error), null)
        }
        break
      case 'hostStop':
        result.success(nativeRuntime.hostStop())
        break
      case 'pickPlugin':
        this.pickPlugin(result)
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

  private async pickPlugin(result: MethodResult): Promise<void> {
    const context = this.context
    if (context === undefined) {
      result.error('picker_unavailable', 'The OHOS file picker context is unavailable.', null)
      return
    }
    try {
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = ['.so']
      options.maxSelectNumber = 1
      const pickerView = new picker.DocumentViewPicker(context as common.UIAbilityContext)
      const selected = await pickerView.select(options)
      if (selected.length === 0) {
        result.success(null)
        return
      }
      const sourceName = selected[0].split('/').pop() ?? 'native-source.so'
      const safeSourceName = sourceName.replace(/[^A-Za-z0-9._-]/g, '_')
      const target = `${context.cacheDir}/${safeSourceName}-${Date.now()}.so`
      try {
        await this.copyFile(selected[0], target)
        result.success({ path: target })
      } catch (error) {
        try {
          fs.unlinkSync(target)
        } catch (_) {
          // The destination may not have been created; preserve the copy error.
        }
        result.error('picker_failed', String(error), null)
      }
    } catch (error) {
      result.error('picker_failed', String(error), null)
    }
  }

  private async copyFile(sourcePath: string, targetPath: string): Promise<void> {
    let source: fs.File | undefined
    let target: fs.File | undefined
    try {
      source = await fs.open(sourcePath, fs.OpenMode.READ_ONLY)
      target = await fs.open(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      const buffer = new ArrayBuffer(64 * 1024)
      let read = await fs.read(source.fd, buffer)
      while (read > 0) {
        await fs.write(target.fd, buffer.slice(0, read))
        read = await fs.read(source.fd, buffer)
      }
    } finally {
      if (source !== undefined) await fs.close(source.fd)
      if (target !== undefined) await fs.close(target.fd)
    }
  }
}
