import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/features/lan_sync/data/platform_lan_sync_network_environment.dart';
import 'package:mg_read/platform/platform_capabilities.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

/// OHOS arm64 real-device acceptance for the embedded Node Runtime.
///
/// The test intentionally probes the native host before creating the facade so
/// an x86_64 stub or an unregistered plugin cannot be mistaken for a healthy
/// Runtime.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS arm64 Runtime host is available and responds to ping', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    expect(await PluginRuntime.ohosNodeHostAvailable(), isTrue);

    final capabilities = await PlatformCapabilities.current().probe(refresh: true);
    expect(capabilities.supportsOhosRuntime.available, isTrue);
    expect(capabilities.supportsOhosWebView.available, isTrue);
    expect(capabilities.supportsOhosBackgroundAudio.available, isTrue);
    expect(capabilities.supportsOhosNetworkEvents.available, isTrue);
    expect(capabilities.supportsOhosAppUpdate.available, isFalse);
    expect(capabilities.supportsOhosAppUpdate.reason, 'app_update_market_fallback_required');
    final localAddresses = await OhosSystemClient.getLocalNetworkAddresses();
    debugPrint('OHOS Network Kit local addresses: $localAddresses');
    expect(localAddresses, isNotEmpty);
    expect(await PlatformLanSyncNetworkEnvironment().isLocalNetworkAvailable(), isTrue);

    final productCapabilities = PlatformCapabilities.forOperatingSystem('ohos');
    expect(productCapabilities.supportsOhosSourceHttpTransport, isTrue);
    expect(productCapabilities.supportsOhosWebViewProfileIsolation, isFalse);
    expect(productCapabilities.supportsOhosWebViewCancellation, isTrue);
    expect(productCapabilities.supportsOhosSourceSystemProxy, isTrue);
    expect(productCapabilities.supportsOhosPlayerHttpProxy, isFalse);
    expect(productCapabilities.supportsOhosVideoBufferedPosition, isTrue);
    expect(productCapabilities.supportsOhosVideoEnhancement, isFalse);
    expect(productCapabilities.supportsOhosSystemVolume, isFalse);
    expect(productCapabilities.supportsOhosReaderVolumeKeys, isFalse);

    final runtime = PluginRuntime();
    final ping = await runtime.invoke(const RuntimePingInvocation());
    expect(ping.isHealthy, isTrue);
    expect(ping.nodeVersion, isNotEmpty);
  });
}
