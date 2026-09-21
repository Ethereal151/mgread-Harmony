import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgread_plugin_runtime/src/ohos_browser_session_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('maps a missing native ArkWeb host to stable unsupported', () async {
    const channel = MethodChannel('mgread_plugin_runtime/ohos_browser_session');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException('ArkWeb host is not registered');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final host = OhosBrowserSessionHost(channel: channel);
    await expectLater(
      host.request(
        jobId: 'job-1',
        deadlineUnixMs: DateTime.now().millisecondsSinceEpoch + 1000,
        raw: const <String, Object?>{'operation': 'request'},
      ),
      throwsA(
        isA<OhosBrowserSessionException>().having(
          (error) => error.code,
          'code',
          'unsupported',
        ),
      ),
    );
    await host.dispose();
  });

  test('rejects expired jobs before touching the native channel', () async {
    final host = OhosBrowserSessionHost();
    await expectLater(
      host.request(
        jobId: 'expired',
        deadlineUnixMs: DateTime.now().millisecondsSinceEpoch - 1,
        raw: const <String, Object?>{'operation': 'request'},
      ),
      throwsA(
        isA<OhosBrowserSessionException>().having(
          (error) => error.code,
          'code',
          'timeout',
        ),
      ),
    );
    await host.dispose();
  });

  test('configures and clears the app-scoped ArkWeb proxy override', () async {
    const channel = MethodChannel('mgread_plugin_runtime/ohos_browser_session');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await OhosBrowserSessionHost.configureProxy(
      Uri.parse('http://127.0.0.1:8080'),
    );
    await OhosBrowserSessionHost.configureProxy(null);

    expect(calls.map((call) => call.method), <String>[
      'configureProxy',
      'configureProxy',
    ]);
    expect(calls.first.arguments, <String, Object?>{
      'proxyUri': 'http://127.0.0.1:8080',
    });
    expect(calls.last.arguments, <String, Object?>{'proxyUri': null});
  });
}
