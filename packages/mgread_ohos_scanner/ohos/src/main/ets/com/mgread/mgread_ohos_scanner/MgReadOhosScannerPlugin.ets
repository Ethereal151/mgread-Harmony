import {
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding,
  Log,
} from '@ohos/flutter_ohos'
import common from '@ohos.app.ability.common'
import scanBarcode from '@hms.core.scan.scanBarcode'
import scanCore from '@hms.core.scan.scanCore'

/** Opens the official OHOS Scan Kit UI and returns the decoded QR payload. */
export default class MgReadOhosScannerPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private static readonly TAG = 'MgReadOhosScanner'
  private channel?: MethodChannel
  private context?: common.Context

  getUniqueClassName(): string {
    return 'MgReadOhosScannerPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext()
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mgread/ohos_scanner')
    this.channel.setMethodCallHandler(this)
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    // ScanKit requires the context of the visible UIAbility. The engine
    // binding only exposes an application context, which cannot launch the
    // page-owned default scanning UI on some real devices.
    this.context = binding.getAbility().context
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
      case 'scan':
        this.scan(result)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private async scan(result: MethodResult): Promise<void> {
    if (this.context === undefined) {
      result.error('scanner_unavailable', 'The OHOS application context is not ready.', null)
      return
    }
    try {
      Log.i(MgReadOhosScannerPlugin.TAG, 'startScanForResult')
      const scanResult = await scanBarcode.startScanForResult(this.context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true,
      })
      result.success({
        value: scanResult.originalValue,
        format: String(scanResult.scanType),
      })
    } catch (error) {
      const code = this.errorCode(error)
      Log.e(MgReadOhosScannerPlugin.TAG, 'ScanKit failed: ', error)
      if (code === '1000500002') {
        result.success(null)
        return
      }
      result.error('scan_failed', this.errorMessage(error), code)
    }
  }

  private errorCode(error: Object): string {
    return String((error as Record<string, Any>)['code'] ?? '')
  }

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }
}
