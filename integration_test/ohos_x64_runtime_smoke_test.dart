import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/platform/platform_capabilities.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

/// Verifies that the x64 HAP runs the same embedded Node Runtime as arm64.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS x64 Node Runtime is available and responds to ping', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    expect(await PluginRuntime.ohosNodeHostAvailable(), isTrue);
    final snapshot = await PlatformCapabilities.current().probe(refresh: true);
    expect(snapshot.supportsOhosRuntime.available, isTrue);
    final ping = await PluginRuntime().invoke(const RuntimePingInvocation());
    expect(ping.isHealthy, isTrue);
    expect(ping.nodeVersion, '26.10.0');
  });
}
