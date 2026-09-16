import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/platform/platform_capabilities.dart';

void main() {
  test('OHOS uses its EL2 persistence directory and safe fallbacks', () async {
    final capabilities = PlatformCapabilities.forOperatingSystem('ohos');

    expect((await capabilities.resolvePersistenceRoot()).path, '/data/storage/el2/base/files/persistence');
    expect(capabilities.isOhos, isTrue);
    expect(capabilities.supportsFilePicker, isFalse);
    expect(capabilities.supportsSharing, isFalse);
    expect(capabilities.supportsPackageInfo, isFalse);
    expect(capabilities.supportsExternalUrls, isFalse);
    expect(capabilities.supportsKeepScreenOn, isFalse);
    expect(capabilities.supportsAudioPlayback, isTrue);
    expect(capabilities.supportsVideoPlayback, isTrue);
    expect(capabilities.supportsBarcodeScanning, isTrue);
    expect(capabilities.supportsPluginRuntime, isTrue);
    expect(capabilities.supportsPluginRuntimeNode, isFalse);
    expect(capabilities.supportsApplicationBrightness, isTrue);
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
}
