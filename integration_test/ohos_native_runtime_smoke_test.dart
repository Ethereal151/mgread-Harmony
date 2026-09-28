import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Native Runtime fixed-plugin lifecycle', (tester) async {
    const channel = MethodChannel('mgread_ohos_native_runtime');
    addTearDown(() async => channel.invokeMethod<void>('dispose'));

    final version = await channel.invokeMethod<String>('version');
    expect(version, startsWith('mgread-ohos-native-runtime/0.1.0 abi=1'));

    expect(
      await channel.invokeMethod<int>('create', <String, Object?>{
        'configJson': jsonEncode(<String, String>{'dataRoot': 'private'}),
      }),
      0,
    );
    expect(await channel.invokeMethod<int>('start'), 0);

    final response = await channel.invokeMethod<String>('invoke', <String, Object?>{
      'requestJson': jsonEncode(<String, String>{'requestId': 'native-one', 'method': 'fixed'}),
    });
    expect(response, contains('"ok":true'));
    expect(response, contains('"method":"fixed"'));

    expect(await channel.invokeMethod<int>('cancel', <String, Object?>{'requestId': 'native-cancel'}), 0);
    await expectLater(
      channel.invokeMethod<String>('invoke', <String, Object?>{
        'requestJson': jsonEncode(<String, String>{'requestId': 'native-cancel', 'method': 'fixed'}),
      }),
      throwsA(isA<PlatformException>()),
    );

    expect(await channel.invokeMethod<int>('restart'), 0);
    final restarted = await channel.invokeMethod<String>('invoke', <String, Object?>{
      'requestJson': jsonEncode(<String, String>{'requestId': 'native-two', 'method': 'fixed'}),
    });
    expect(restarted, contains('"ok":true'));
    expect(await channel.invokeMethod<int>('stop'), 0);
  });
}
