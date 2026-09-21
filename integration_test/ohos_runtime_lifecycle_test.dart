import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

/// Real arm64 OHOS evidence for the Runtime facade lifecycle and diagnostics.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Runtime restarts natively and the same facade recovers', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final first = PluginRuntime();
    final firstPing = await first.invoke(const RuntimePingInvocation());
    expect(firstPing.isHealthy, isTrue);
    expect(
      first.latestDiagnostics.map((diagnostic) => diagnostic.code),
      containsAllInOrder(<String>['runtime_facade_invoke_started', 'runtime_facade_invoke_completed']),
    );
    for (final diagnostic in first.latestDiagnostics) {
      expect(diagnostic.message, isNot(contains('http://')));
      expect(diagnostic.message, isNot(contains('https://')));
      expect(diagnostic.message, isNot(contains('token')));
      expect(diagnostic.message, isNot(contains('signature')));
    }

    await const MethodChannel('mgread_plugin_runtime/ohos').invokeMethod<String>('restart');
    final secondPing = await first.invoke(const RuntimePingInvocation());
    expect(secondPing.isHealthy, isTrue);
    expect(secondPing.nodeVersion, isNotEmpty);
    expect(
      first.latestDiagnostics.map((diagnostic) => diagnostic.code),
      containsAllInOrder(<String>[
        'runtime_facade_invoke_started',
        'runtime_facade_invoke_completed',
        'runtime_facade_invoke_started',
        'runtime_facade_invoke_completed',
      ]),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
