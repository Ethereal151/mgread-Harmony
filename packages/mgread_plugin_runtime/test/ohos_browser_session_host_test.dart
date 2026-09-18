import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgread_plugin_runtime/src/ohos_browser_session_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'maps a missing native ArkWeb host to stable unsupported',
    () async {
      const channel = MethodChannel(
        'mgread_plugin_runtime/ohos_browser_session',
      );
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
    },
  );

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
}
