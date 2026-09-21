import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/platform/platform_capabilities.dart';
import 'package:mg_read/platform/platform_system_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mgread/ohos_system');
  final ohos = PlatformCapabilities.forOperatingSystem('ohos');
  final uri = Uri.parse('https://example.com/help');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('OHOS external URI bridge reports a successful native open', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    expect(await openExternalUri(uri, capabilities: ohos), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openUri');
    expect((calls.single.arguments as Map<Object?, Object?>)['uri'], uri.toString());
  });

  test('OHOS external URI bridge preserves a native refusal', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => false);

    expect(await openExternalUri(uri, capabilities: ohos), isFalse);
  });

  test('OHOS external URI bridge lets native exceptions reach the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'uri_open_failed'),
    );

    expect(openExternalUri(uri, capabilities: ohos), throwsA(isA<PlatformException>()));
  });
}
