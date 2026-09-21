import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/platform/platform_capabilities.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

/// The x64 emulator is intentionally a non-Runtime target. This test proves
/// that the same HAP reports the architecture limitation instead of entering
/// a half-started embedded Node process.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS x64 reports a stable Runtime architecture downgrade', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    expect(await PluginRuntime.ohosNodeHostAvailable(), isFalse);
    final snapshot = await PlatformCapabilities.current().probe(refresh: true);
    expect(snapshot.supportsOhosRuntime.available, isFalse);
    expect(snapshot.supportsOhosRuntime.reason, 'native_node_host_unavailable');
    expect(snapshot.supportsOhosRuntime.architecture, contains('x86'));
  });
}
