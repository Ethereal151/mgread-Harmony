import 'package:flutter_test/flutter_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

void main() {
  test('keeps OHOS native-only capability calls typed and unsupported', () async {
    final runtime = PluginRuntime.ohosNativeForTesting();
    addTearDown(runtime.debugDispose);

    expect(runtime.supportsNativeSources, isFalse);
    expect(runtime.debugDesktopProcessStartCount, 0);

    await expectLater(
      runtime.invoke(const RuntimePingInvocation()),
      throwsA(
        isA<PluginRuntimeException>()
            .having((error) => error.code, 'error code', 'unsupported')
            .having(
              (error) => error.message,
              'message',
              'The OHOS native Runtime is not staged; use the default Node Runtime.',
            ),
      ),
    );
    await expectLater(
      runtime.configurePluginHttpProxy(Uri.parse('http://127.0.0.1:8080')),
      throwsA(isA<PluginRuntimeException>()),
    );
    expect(
      () => runtime.importNativeLocalPlugin(),
      throwsA(isA<PluginRuntimeException>()),
    );
  });
}
