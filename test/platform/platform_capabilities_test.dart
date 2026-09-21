import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/platform/platform_capabilities.dart';

void main() {
  test('OHOS uses its EL2 persistence directory and safe fallbacks', () async {
    final capabilities = PlatformCapabilities.forOperatingSystem('ohos');

    expect((await capabilities.resolvePersistenceRoot()).path, '/data/storage/el2/base/haps/entry/files/persistence');
    expect(capabilities.isOhos, isTrue);
    expect(capabilities.supportsFilePicker, isTrue);
    expect(capabilities.supportsSharing, isTrue);
    expect(capabilities.supportsPackageInfo, isTrue);
    expect(capabilities.supportsExternalUrls, isTrue);
    expect(capabilities.supportsKeepScreenOn, isTrue);
    expect(capabilities.supportsAudioPlayback, isTrue);
    expect(capabilities.supportsVideoPlayback, isTrue);
    expect(capabilities.supportsBarcodeScanning, isTrue);
    expect(capabilities.supportsPluginRuntime, isTrue);
    expect(capabilities.supportsPluginRuntimeNode, isTrue);
    expect(capabilities.supportsApplicationBrightness, isTrue);
    expect(capabilities.supportsOhosSourceHttpTransport, isTrue);
    expect(capabilities.supportsOhosWebViewProfileIsolation, isFalse);
    expect(capabilities.supportsOhosWebViewCancellation, isTrue);
    expect(capabilities.supportsOhosSourceSystemProxy, isTrue);
    expect(capabilities.supportsOhosPlayerHttpProxy, isFalse);
    expect(capabilities.supportsOhosVideoBufferedPosition, isTrue);
    expect(capabilities.supportsOhosVideoEnhancement, isFalse);
    expect(capabilities.supportsOhosSystemVolume, isFalse);
    expect(capabilities.supportsOhosReaderVolumeKeys, isFalse);
  });

  test('desktop capabilities retain their existing responsibilities', () {
    final capabilities = PlatformCapabilities.forOperatingSystem('windows');

    expect(capabilities.supportsFilePicker, isTrue);
    expect(capabilities.supportsSharing, isTrue);
    expect(capabilities.supportsWindowManagement, isTrue);
    expect(capabilities.supportsPluginRuntime, isTrue);
    expect(capabilities.supportsKeepScreenOn, isTrue);
    expect(capabilities.supportsApplicationBrightness, isFalse);
    expect(capabilities.supportsAudioPlayback, isTrue);
    expect(capabilities.supportsVideoPlayback, isTrue);
    expect(capabilities.supportsBarcodeScanning, isTrue);
  });

  test('non-OHOS capability probe is explicit and never touches a channel', () async {
    final snapshot = await PlatformCapabilities.forOperatingSystem('windows').probe();

    expect(snapshot.supportsOhosRuntime.available, isFalse);
    expect(snapshot.supportsOhosRuntime.reason, 'not_ohos');
    expect(snapshot.supportsOhosRuntime.apiVersion, 'unknown');
    expect(snapshot.supportsOhosRuntime.architecture, 'unknown');
    expect(snapshot['supportsOhosNetworkEvents'].available, isFalse);
  });
}
