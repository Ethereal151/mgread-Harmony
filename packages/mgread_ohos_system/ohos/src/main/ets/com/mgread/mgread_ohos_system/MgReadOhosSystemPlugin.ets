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
import bundleManager from '@ohos.bundle.bundleManager'
import filePicker from '@ohos.file.picker'
import fileUri from '@ohos.file.fileuri'
import fs from '@ohos.file.fs'
import wantConstant from '@ohos.ability.wantConstant'

/** Owns file picker, package metadata, sharing, and external URI intents on OHOS. */
export default class MgReadOhosSystemPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel
  private context?: common.UIAbilityContext

  getUniqueClassName(): string {
    return 'MgReadOhosSystemPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread/ohos_system')
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
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'pickImportFile':
        this.pickImportFile(result)
        break
      case 'exportFile':
        this.exportFile(call.args as Map<string, Object> | null, result)
        break
      case 'shareFile':
        this.shareFile(call.args as Map<string, Object> | null, result)
        break
      case 'openUri':
        this.openUri(call.args as Map<string, Object> | null, result)
        break
      case 'getPackageInfo':
        this.getPackageInfo(result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private async pickImportFile(result: MethodResult): Promise<void> {
    if (this.context === undefined) {
      result.error('system_unavailable', 'The OHOS UIAbility context is not ready.', null)
      return
    }
    try {
      const options = new filePicker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['.mgread']
      const selected = await new filePicker.DocumentViewPicker(this.context).select(options)
      if (selected.length === 0) {
        result.success(null)
        return
      }
      const target = `${this.context.cacheDir}/mgread-import-${Date.now()}.mgread`
      try {
        this.copyFile(selected[0], target)
        result.success(target)
      } catch (error) {
        try {
          fs.unlinkSync(target)
        } catch (_) {
          // The destination may not have been created; preserve the copy error.
        }
        result.error('pick_failed', this.errorMessage(error), null)
      }
    } catch (error) {
      result.error('pick_failed', this.errorMessage(error), null)
    }
  }

  private async exportFile(args: Map<string, Object> | null, result: MethodResult): Promise<void> {
    if (this.context === undefined) {
      result.error('system_unavailable', 'The OHOS UIAbility context is not ready.', null)
      return
    }
    const path = args?.get('path')
    const suggestedName = args?.get('suggestedName')
    if (typeof path !== 'string' || typeof suggestedName !== 'string' || path.length === 0 || suggestedName.length === 0) {
      result.error('invalid_argument', 'path and suggestedName are required.', null)
      return
    }
    try {
      const options = new filePicker.DocumentSaveOptions()
      options.newFileNames = [suggestedName]
      options.fileSuffixChoices = ['.mgread']
      const destinations = await new filePicker.DocumentViewPicker(this.context).save(options)
      if (destinations.length === 0) {
        result.success(false)
        return
      }
      this.copyFile(path, destinations[0])
      result.success(true)
    } catch (error) {
      result.error('export_failed', this.errorMessage(error), null)
    }
  }

  private async shareFile(args: Map<string, Object> | null, result: MethodResult): Promise<void> {
    const path = args?.get('path')
    if (this.context === undefined || typeof path !== 'string' || path.length === 0) {
      result.error('invalid_argument', 'A local file path and UIAbility context are required.', null)
      return
    }
    try {
      const uri = fileUri.getUriFromPath(path)
      const parameters: Record<string, Object> = {}
      parameters['ability.params.stream'] = [uri]
      await this.context.startAbility({
        action: wantConstant.Action.ACTION_SEND_DATA,
        type: 'application/octet-stream',
        uri,
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
        parameters,
      })
      result.success(true)
    } catch (error) {
      result.error('share_failed', this.errorMessage(error), null)
    }
  }

  private async openUri(args: Map<string, Object> | null, result: MethodResult): Promise<void> {
    const uri = args?.get('uri')
    if (this.context === undefined || typeof uri !== 'string' || uri.length === 0) {
      result.error('invalid_argument', 'A URI and UIAbility context are required.', null)
      return
    }
    try {
      await this.context.startAbility({action: wantConstant.Action.ACTION_VIEW_DATA, uri})
      result.success(true)
    } catch (error) {
      result.error('open_uri_failed', this.errorMessage(error), null)
    }
  }

  private async getPackageInfo(result: MethodResult): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      result.success({version: info.versionName, build: info.versionCode})
    } catch (error) {
      result.error('package_info_failed', this.errorMessage(error), null)
    }
  }

  private copyFile(sourcePath: string, targetPath: string): void {
    let source: fs.File | undefined
    let target: fs.File | undefined
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY)
      target = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      const buffer = new ArrayBuffer(64 * 1024)
      let read = fs.readSync(source.fd, buffer)
      while (read > 0) {
        fs.writeSync(target.fd, buffer.slice(0, read))
        read = fs.readSync(source.fd, buffer)
      }
    } finally {
      if (source !== undefined) fs.closeSync(source.fd)
      if (target !== undefined) fs.closeSync(target.fd)
    }
  }

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }
}
