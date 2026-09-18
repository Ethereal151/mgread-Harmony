import {
  Any,
  AbilityAware,
  AbilityPluginBinding,
  EventChannel,
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
import connection from '@ohos.net.connection'
import deviceInfo from '@ohos.deviceInfo'
import wantConstant from '@ohos.ability.wantConstant'
import OhosNetworkEventStreamHandler from './OhosNetworkEventStreamHandler'

interface OhosCapabilityProbePayload {
  available: boolean
  reason: string
  apiVersion: string
  architecture: string
}

interface OhosCapabilitySnapshotPayload {
  supportsOhosRuntime: OhosCapabilityProbePayload
  supportsOhosWebView: OhosCapabilityProbePayload
  supportsOhosBackgroundAudio: OhosCapabilityProbePayload
  supportsOhosAppUpdate: OhosCapabilityProbePayload
  supportsOhosNetworkEvents: OhosCapabilityProbePayload
}

/** Owns file picker, package metadata, sharing, and external URI intents on OHOS. */
export default class MgReadOhosSystemPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel
  private eventChannel?: EventChannel
  private context?: common.UIAbilityContext
  private readonly networkEvents = new OhosNetworkEventStreamHandler()
  private networkConnection?: connection.NetConnection

  getUniqueClassName(): string {
    return 'MgReadOhosSystemPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread/ohos_system')
    this.channel.setMethodCallHandler(this)
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'mgread/network_environment/events')
    this.eventChannel.setStreamHandler(this.networkEvents)
    this.attachNetworkEvents()
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context as common.UIAbilityContext
  }

  onDetachedFromAbility(): void {
    this.context = undefined
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.eventChannel?.setStreamHandler(null)
    this.channel = undefined
    this.eventChannel = undefined
    this.context = undefined
    const network = this.networkConnection
    this.networkConnection = undefined
    if (network !== undefined) {
      network.unregister((_error: Object | undefined): void => {})
    }
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
      case 'getDeviceInfo':
        this.getDeviceInfo(result)
        break
      case 'isLocalNetworkAvailable':
        this.isLocalNetworkAvailable(result)
        break
      case 'getCapabilities':
        this.getCapabilities(result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private async isLocalNetworkAvailable(result: MethodResult): Promise<void> {
    try {
      result.success(await connection.hasDefaultNet())
    } catch (error) {
      result.error('network_probe_failed', this.errorMessage(error), null)
    }
  }

  private async getCapabilities(result: MethodResult): Promise<void> {
    const architecture = deviceInfo.abiList.trim().length > 0 ? deviceInfo.abiList.trim() : 'unknown'
    const apiVersion = deviceInfo.sdkApiVersion > 0 ? `API ${deviceInfo.sdkApiVersion}` : 'unknown'
    const networkEventsAvailable = this.networkConnection !== undefined
    const snapshot: OhosCapabilitySnapshotPayload = {
      supportsOhosRuntime: this.probe(true, 'native_runtime', apiVersion, architecture),
      supportsOhosWebView: this.probe(true, 'arkweb_native_bridge_registered', apiVersion, architecture),
      supportsOhosBackgroundAudio: this.probe(true, 'avsession_native_bridge_registered', apiVersion, architecture),
      supportsOhosAppUpdate: this.probe(false, 'install_bundle_signature_permission_required', 'unknown', architecture),
      supportsOhosNetworkEvents: this.probe(
        networkEventsAvailable,
        networkEventsAvailable ? 'network_kit' : 'network_kit_unavailable',
        apiVersion,
        architecture,
      ),
    }
    result.success(snapshot)
  }

  private probe(available: boolean, reason: string, apiVersion: string, architecture: string): OhosCapabilityProbePayload {
    return {available, reason, apiVersion, architecture}
  }

  private attachNetworkEvents(): void {
    try {
      const network = connection.createNetConnection()
      network.on('netAvailable', (_handle: connection.NetHandle): void => this.networkEvents.emit(true))
      network.on('netLost', (_handle: connection.NetHandle): void => this.networkEvents.emit(false))
      network.on('netUnavailable', (): void => this.networkEvents.emit(false))
      network.register((_error: Object | undefined): void => {})
      this.networkConnection = network
    } catch (_) {
      this.networkConnection = undefined
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

  private getDeviceInfo(result: MethodResult): void {
    try {
      const model = deviceInfo.productModel
      const alias = deviceInfo.productModelAlias
      result.success({model, label: alias.length > 0 ? alias : model})
    } catch (error) {
      result.error('device_info_failed', this.errorMessage(error), null)
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
