import {
  Any,
  AbilityAware,
  AbilityPluginBinding,
  FlutterAssets,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  EventChannel,
} from '@ohos/flutter_ohos'
import fs from '@ohos.file.fs'
import common from '@ohos.app.ability.common'
import { picker } from '@kit.CoreFileKit'
import mgreadNodeHost from 'libmgread_node_host.so'
import OhosRuntimeProgressStreamHandler from './OhosRuntimeProgressStreamHandler'
import OhosArkWebHost from './OhosArkWebHost'

const RUNTIME_ASSET_PATH = 'packages/mgread_plugin_runtime/assets/runtime/ohos'
const RUNTIME_DIRECTORY = 'mgread-runtime/ohos'

/**
 * OHOS Runtime bridge.
 *
 * The bridge keeps all Node VM/process ownership inside the native host.
 */
export default class OhosRuntimePlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel
  private progressChannel?: EventChannel
  private browserChannel?: MethodChannel
  private browserEventChannel?: EventChannel
  private browserHost?: OhosArkWebHost
  private progressHandler = new OhosRuntimeProgressStreamHandler()
  private context?: common.UIAbilityContext
  private assets?: FlutterAssets
  private runtimeReady = false
  private runtimeInitialization?: Promise<void>

  getUniqueClassName(): string {
    return 'OhosRuntimePlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.assets = binding.getFlutterAssets()
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread_plugin_runtime/ohos')
    this.channel.setMethodCallHandler(this)
    this.progressChannel = new EventChannel(binding.getBinaryMessenger(), 'mgread_plugin_runtime/ohos/progress')
    this.progressChannel.setStreamHandler(this.progressHandler)
    this.browserHost = new OhosArkWebHost()
    this.browserHost.register(binding.getPlatformViewRegistry())
    this.browserChannel = new MethodChannel(binding.getBinaryMessenger(), 'mgread_plugin_runtime/ohos_browser_session')
    this.browserChannel.setMethodCallHandler(this.browserHost)
    this.browserEventChannel = new EventChannel(binding.getBinaryMessenger(), 'mgread_plugin_runtime/ohos_browser_session/events')
    this.browserEventChannel.setStreamHandler(this.browserHost.getStreamHandler())
    mgreadNodeHost.setBrowserSessionCallback((requestId: string, payload: string): void => {
      this.forwardBrowserRequest(requestId, payload)
    })
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
    this.progressChannel?.setStreamHandler(null)
    this.progressChannel = undefined
    this.browserChannel?.setMethodCallHandler(null)
    this.browserChannel = undefined
    this.browserEventChannel?.setStreamHandler(null)
    this.browserEventChannel = undefined
    this.browserHost?.dispose()
    this.browserHost = undefined
    mgreadNodeHost.clearBrowserSessionCallback()
    if (this.runtimeReady) mgreadNodeHost.dispose()
    this.context = undefined
    this.assets = undefined
    this.runtimeReady = false
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'cancelInvocation':
        this.cancel(call.args as Map<string, Object> | null)
        result.success(null)
        break
      case 'dispose':
        if (this.runtimeReady) mgreadNodeHost.dispose()
        this.runtimeReady = false
        result.success(null)
        break
      case 'invoke':
        this.invoke(call.args as Map<string, Object> | null, result)
        break
      case 'runtimePaths':
        this.ensureRuntime()
          .then(() => result.success(mgreadNodeHost.runtimePaths()))
          .catch((error: Object) => result.error('runtime_start_failed', this.errorMessage(error), null))
        break
      case 'nativeNodeHostAvailable':
        result.success(mgreadNodeHost.nativeNodeHostAvailable())
        break
      case 'materializeTransfer':
        this.ensureRuntime()
          .then(() => {
          const args = call.args as Map<string, Object> | null
          result.success(mgreadNodeHost.materializeTransfer(
            String(args?.get('token') ?? ''),
            String(args?.get('destination') ?? ''),
          ))
          })
          .catch((error: Object) => result.error('runtime_transfer_failed', this.errorMessage(error), null))
        break
      case 'restart':
        try {
          result.success(mgreadNodeHost.restart())
        } catch (error) {
          result.error('runtime_restart_failed', this.errorMessage(error), null)
        }
        break
      case 'pickLocalPlugin':
        this.pickLocalPlugin(result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private cancel(args: Map<string, Object> | null): void {
    mgreadNodeHost.cancelInvocation(String(args?.get('requestId') ?? ''))
  }

  private forwardBrowserRequest(requestId: string, payload: string): void {
    const host = this.browserHost
    if (host === undefined) {
      mgreadNodeHost.resolveBrowserSession(requestId, JSON.stringify({__mgreadBrowserSessionError: 'unsupported'}))
      return
    }
    host.requestJson(payload)
      .then((response: Any): void => {
        mgreadNodeHost.resolveBrowserSession(requestId, JSON.stringify(this.toJsonValue(response)))
      })
      .catch((error: Object): void => {
        mgreadNodeHost.resolveBrowserSession(requestId, JSON.stringify({
          __mgreadBrowserSessionError: this.browserErrorCode(error),
        }))
      })
  }

  private browserErrorCode(error: Object): string {
    const values = error as Record<string, Any>
    const code = String(values['code'] ?? values['message'] ?? '')
    switch (code) {
      case 'cancelled':
      case 'interaction_required':
      case 'overloaded':
      case 'plugin_execution_failed':
      case 'timeout':
      case 'unsupported':
        return code
      default:
        return 'plugin_execution_failed'
    }
  }

  private invoke(args: Map<string, Object> | null, result: MethodResult): void {
    const invokeNative = (): void => {
      try {
        const method = String(args?.get('method') ?? '')
        const pending: Promise<string> = mgreadNodeHost.invokeAsync(
          String(args?.get('requestId') ?? ''),
          method,
          this.encodeParams(args?.get('params')),
          Number(args?.get('deadlineUnixMs') ?? 0),
        )
        pending
          .then((encoded: string): void => result.success(encoded))
          .catch((error: Object): void => result.error('runtime_invocation_failed', this.errorMessage(error), null))
      } catch (error) {
        result.error('runtime_invocation_failed', this.errorMessage(error), null)
      }
    }
    if (this.runtimeReady) {
      invokeNative()
      return
    }
    this.ensureRuntime()
      .then(invokeNative)
      .catch((error: Object) => result.error('runtime_invocation_failed', this.errorMessage(error), null))
  }

  private async pickLocalPlugin(result: MethodResult): Promise<void> {
    const context = this.context
    if (context === undefined) {
      result.error('picker_unavailable', 'The OHOS file picker context is unavailable.', null)
      return
    }
    try {
      const options = new picker.DocumentSelectOptions()
      // HarmonyOS 7 on API 26 treats a multi-dot suffix such as
      // ".mgplugin.js" as a plain ".js" filter and hides the artifact.
      // Let the picker show files, then enforce the two accepted artifact
      // names below before copying the selected document URI.
      options.fileSuffixFilters = ['All files (.)|.*']
      options.maxSelectNumber = 1
      const pickerView = new picker.DocumentViewPicker(context as common.UIAbilityContext)
      let selected: Array<string>
      try {
        selected = await pickerView.select(options)
      } catch (error) {
        result.error('picker_failed', this.errorMessage(error), null)
        return
      }
      if (selected.length === 0) {
        result.success('')
        return
      }
      const selectedUri = selected[0]
      const lowerUri = selectedUri.toLowerCase()
      let suffix: string
      if (lowerUri.endsWith('.mgplugin.js')) {
        suffix = '.mgplugin.js'
      } else if (lowerUri.endsWith('.mgplugin')) {
        suffix = '.mgplugin'
      } else {
        result.error('file_name_invalid', 'The selected file is not a MgRead plugin artifact.', null)
        return
      }
      const target = `${context.cacheDir}/mgread-plugin-import-${Date.now()}${suffix}`
      try {
        await this.copyFile(selectedUri, target)
      } catch (error) {
        result.error('file_read_failed', this.errorMessage(error), null)
        return
      }
      result.success(target)
    } catch (error) {
      result.error('picker_failed', this.errorMessage(error), null)
    }
  }

  private ensureRuntime(): Promise<void> {
    if (this.runtimeReady) return Promise.resolve()
    const pending = this.runtimeInitialization
    if (pending !== undefined) return pending
    const initialization = Promise.resolve().then(() => this.startRuntime())
    this.runtimeInitialization = initialization
    initialization.then(
      () => {
        if (this.runtimeInitialization === initialization) this.runtimeInitialization = undefined
      },
      () => {
        if (this.runtimeInitialization === initialization) this.runtimeInitialization = undefined
      },
    )
    return initialization
  }

  private startRuntime(): void {
    if (this.runtimeReady) return
    const context = this.context
    const assets = this.assets
    if (context === undefined || assets === undefined) throw new Error('The OHOS Runtime context is not ready.')
    const runtimeRoot = `${context.filesDir}/${RUNTIME_DIRECTORY}`
    this.copyRuntimeAssets(assets.getAssetFilePathBySubpath(RUNTIME_ASSET_PATH), runtimeRoot)
    if (mgreadNodeHost.runtimeVersion() !== '24.16.0') {
      throw new Error('The OHOS Node host version is not supported.')
    }
    const dataRoot = `${context.filesDir}/mgread-runtime/data`
    const inboxRoot = `${context.filesDir}/mgread-runtime/import-inbox`
    this.makeDirectory(dataRoot)
    this.makeDirectory(inboxRoot)
    mgreadNodeHost.setProgressCallback((payload: string): void => {
      try { this.progressHandler.emit(JSON.parse(payload) as Any) } catch (_) { /* diagnostic only */ }
    })
    mgreadNodeHost.initialize(runtimeRoot, dataRoot, inboxRoot)
    this.runtimeReady = true
  }

  private copyRuntimeAssets(sourceRoot: string, destinationRoot: string): void {
    this.makeDirectory(destinationRoot)
    const entries = this.context?.resourceManager.getRawFileListSync(sourceRoot) ?? []
    for (const entry of entries) {
      const source = `${sourceRoot}/${entry}`
      const destination = `${destinationRoot}/${entry}`
      try {
        const content = this.context?.resourceManager.getRawFileContentSync(source)
        if (content === undefined) continue
        this.makeDirectory(destination.substring(0, destination.lastIndexOf('/')))
        const file = fs.openSync(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
        fs.writeSync(file.fd, content.buffer)
        fs.closeSync(file.fd)
      } catch (_) {
        this.copyRuntimeAssets(source, destination)
      }
    }
  }

  private makeDirectory(path: string): void {
    if (path.length === 0) return
    try { fs.mkdirSync(path, true) } catch (_) { /* already exists */ }
  }

  private encodeParams(value: Any | undefined): string {
    return JSON.stringify(this.toJsonValue(value ?? {}))
  }

  /**
   * StandardMethodCodec preserves nested Dart maps as ArkTS Map instances.
   * JSON.stringify serializes those maps as `{}`, so normalize the complete
   * request tree before handing it to the embedded Node Runtime.
   */
  private toJsonValue(value: Any): Any {
    if (value instanceof Map) {
      const object: Record<string, Any> = {}
      value.forEach((entry: Any, key: string): void => {
        object[key] = this.toJsonValue(entry)
      })
      return object
    }
    if (Array.isArray(value)) {
      return value.map((entry: Any): Any => this.toJsonValue(entry))
    }
    return value
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

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }
}
