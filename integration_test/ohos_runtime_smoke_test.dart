import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

    final runtime = PluginRuntime();
    final ping = await runtime.invoke(const RuntimePingInvocation());
    expect(ping.isHealthy, isTrue);
    expect(ping.nodeVersion, isNotEmpty);
  });
}
