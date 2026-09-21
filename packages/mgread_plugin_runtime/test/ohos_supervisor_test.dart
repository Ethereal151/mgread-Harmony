import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mgread_plugin_runtime/ohos');
  late PluginRuntime runtime;

  setUp(() {
    runtime = PluginRuntime.ohosForTesting();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await runtime.debugDispose();
  });

  test(
    'records OHOS invoke lifecycle and exposes a bounded immutable snapshot',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'invoke');
            return jsonEncode(<String, Object?>{
              'ok': true,
              'result': <String, Object?>{
                'ok': true,
                'nodeVersion': 'v24.16.0',
                'runtimeVersion': 'test',
              },
            });
          });

      final result = await runtime.invoke(const RuntimePingInvocation());

      expect(result.isHealthy, isTrue);
      expect(
        runtime.latestDiagnostics.map((diagnostic) => diagnostic.code),
        <String>[
          'runtime_facade_invoke_started',
          'runtime_facade_invoke_completed',
        ],
      );
      expect(
        () => runtime.latestDiagnostics.add(runtime.latestDiagnostics.first),
        throwsUnsupportedError,
      );
    },
  );

  test('records stable rejection and bridge-failure diagnostics', () async {
    var bridgeFailure = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (bridgeFailure) throw PlatformException(code: 'bridge_failed');
          return jsonEncode(<String, Object?>{
            'ok': false,
            'error': <String, Object?>{
              'code': 'unsupported',
              'message': 'unsupported in test',
            },
          });
        });

    await expectLater(
      runtime.invoke(const RuntimePingInvocation()),
      throwsA(isA<PluginRuntimeException>()),
    );
    bridgeFailure = true;
    await expectLater(
      runtime.invoke(const RuntimePingInvocation()),
      throwsA(isA<PluginRuntimeException>()),
    );

    expect(
      runtime.latestDiagnostics.map((diagnostic) => diagnostic.code),
      <String>[
        'runtime_facade_invoke_started',
        'runtime_facade_invoke_rejected',
        'runtime_facade_invoke_started',
        'runtime_facade_invoke_bridge_failed',
      ],
    );
  });
}
