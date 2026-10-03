import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
                'nodeVersion': 'v26.10.0',
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

  test(
    'waits for an admitted invocation before restarting the OHOS VM',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mgread-ohos-supervisor-',
      );
      final inbox = Directory('${root.path}${Platform.pathSeparator}inbox');
      await inbox.create(recursive: true);
      final artifact = File(
        '${root.path}${Platform.pathSeparator}source.mgplugin.js',
      );
      await artifact.writeAsString('test artifact');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final invokeStarted = Completer<void>();
      final releaseInvoke = Completer<void>();
      var restartCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'invoke':
                if (!invokeStarted.isCompleted) {
                  invokeStarted.complete();
                  await releaseInvoke.future;
                }
                return jsonEncode(<String, Object?>{
                  'ok': true,
                  'result': <String, Object?>{
                    'ok': true,
                    'nodeVersion': 'v26.10.0',
                    'runtimeVersion': 'test',
                  },
                });
              case 'runtimePaths':
                return jsonEncode(<String, Object?>{
                  'dataRoot': root.path,
                  'inboxRoot': inbox.path,
                });
              case 'restart':
                restartCalled = true;
                return '{}';
              default:
                return null;
            }
          });

      final inFlight = runtime.invoke(const RuntimePingInvocation());
      await invokeStarted.future;
      final importing = runtime.importLocalPluginForTesting(artifact.path);
      await Future<void>.delayed(Duration.zero);
      expect(restartCalled, isFalse);

      releaseInvoke.complete();
      await inFlight;
      await importing;
      expect(restartCalled, isTrue);
    },
  );
}
