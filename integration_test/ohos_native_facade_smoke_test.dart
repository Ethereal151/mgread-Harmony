import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Native Runtime Facade completes the data-source inspection', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final runtime = PluginRuntime();
    addTearDown(runtime.debugDispose);

    final ping = await runtime.invoke(const RuntimePingInvocation()).timeout(const Duration(seconds: 10));
    expect(ping.isHealthy, isTrue);

    final plugins = await runtime.invoke(const InstalledPluginsInvocation()).timeout(const Duration(seconds: 10));
    expect(plugins, hasLength(1));
    expect(plugins.single.id, 'org.mgread.aisishuwu.native');
    expect(plugins.single.engine, PluginEngine.native);
    expect(plugins.single.displayName, '爱丽丝书屋（Rust）');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
