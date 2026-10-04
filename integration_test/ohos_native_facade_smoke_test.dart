import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Native Runtime Facade completes the data-source inspection', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final runtime = PluginRuntime();

    final ping = await _invokeWithFrames(tester, runtime.invoke(const RuntimePingInvocation()).timeout(const Duration(seconds: 10)));
    expect(ping.isHealthy, isTrue);
    final runtimeStatus = await _invokeWithFrames(
      tester,
      runtime.invoke(const RuntimeStatusInvocation()).timeout(const Duration(seconds: 10)),
    );
    const architecture = String.fromEnvironment('MGREAD_OHOS_ARCH', defaultValue: 'arm64');
    expect(runtimeStatus.nativeStatus?.arch, architecture == 'x64' ? 'x86_64' : 'arm64-v8a');

    final plugins = await _invokeWithFrames(
      tester,
      runtime.invoke(const InstalledPluginsInvocation()).timeout(const Duration(seconds: 10)),
    );
    expect(plugins, hasLength(1));
    expect(plugins.single.id, 'org.mgread.aisishuwu.native');
    expect(plugins.single.engine, PluginEngine.native);
    expect(plugins.single.displayName, '爱丽丝书屋（Rust）');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<T> _invokeWithFrames<T>(WidgetTester tester, Future<T> invocation) async {
  var completed = false;
  T? value;
  Object? failure;
  StackTrace? failureStack;
  invocation.then<void>(
    (result) {
      value = result;
      completed = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      failure = error;
      failureStack = stackTrace;
      completed = true;
    },
  );
  while (!completed) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return value as T;
}
