import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/platform/platform_capabilities.dart';
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
    expect(capabilities.supportsOhosAppUpdate.reason, 'install_bundle_signature_permission_required');

    final runtime = PluginRuntime();
    final ping = await runtime.invoke(const RuntimePingInvocation());
    expect(ping.isHealthy, isTrue);
    expect(ping.nodeVersion, isNotEmpty);
  });
}
