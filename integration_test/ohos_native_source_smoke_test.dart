import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Native Runtime executes the Alice source chain', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    const channel = MethodChannel('mgread_ohos_native_runtime');
    addTearDown(() async => channel.invokeMethod<void>('dispose'));
    final proxyEnvironment = await readSystemProxyEnvironment();
    const forcedProxy = String.fromEnvironment('MGREAD_OHOS_TEST_PROXY');
    final proxy = forcedProxy.isNotEmpty ? forcedProxy : (proxyEnvironment['HTTPS_PROXY'] ?? proxyEnvironment['HTTP_PROXY']);
    final proxyConfig = proxy == null ? const <String, String>{} : <String, String>{'proxy': proxy};

    expect(
      await channel.invokeMethod<int>('create', <String, Object?>{
        'configJson': jsonEncode(<String, String>{'dataRoot': 'private', ...proxyConfig}),
      }),
      0,
    );
    expect(await channel.invokeMethod<int>('start'), 0);

    Future<Map<String, dynamic>> invoke(String requestId, Map<String, dynamic> request) async {
      String? encoded;
      try {
        encoded = await channel.invokeMethod<String>('invoke', <String, Object?>{
          'requestJson': jsonEncode(<String, dynamic>{'requestId': requestId, 'method': request['method'], 'request': request['request']}),
        });
      } on PlatformException catch (error) {
        final diagnostic = await channel.invokeMethod<String>('lastError');
        fail('Native source invocation failed: $error; diagnostic=$diagnostic');
      }
      final value = jsonDecode(encoded!) as Map<String, dynamic>;
      expect(value['ok'], isTrue, reason: encoded);
      expect(value['engine'], 'ohos-native');
      expect(value['sourceId'], 'org.mgread.aisishuwu.native');
      return value['value'] as Map<String, dynamic>;
    }

    final discovered = await invoke('alice-discover', <String, dynamic>{
      'method': 'discover',
      'request': <String, dynamic>{'target': null, 'cursor': null, 'collectionId': null, 'pageSize': 12},
    });
    final components = (discovered['document'] as Map<String, dynamic>)['components'] as List<dynamic>;
    final home =
        components.firstWhere((component) => (component as Map<String, dynamic>)['type'] == 'contentCollection') as Map<String, dynamic>;
    final items = home['items'] as List<dynamic>;
    expect(items, isNotEmpty);
    final firstContent = (items.first as Map<String, dynamic>)['content'] as Map<String, dynamic>;
    final contentId = firstContent['id'] as String;
    final title = firstContent['title'] as String;

    final search = await invoke('alice-search', <String, dynamic>{
      'method': 'search',
      'request': <String, dynamic>{'query': title, 'cursor': null, 'pageSize': 10},
    });
    expect(search['items'], isA<List<dynamic>>());

    final detail = await invoke('alice-detail', <String, dynamic>{
      'method': 'getDetail',
      'request': <String, dynamic>{'id': contentId},
    });
    expect(detail['id'], contentId);
    final catalog = await invoke('alice-chapters', <String, dynamic>{
      'method': 'getChapters',
      'request': <String, dynamic>{'id': contentId},
    });
    final chapters = catalog['items'] as List<dynamic>;
    expect(chapters, isNotEmpty);
    final chapter = chapters.first as Map<String, dynamic>;
    final content = await invoke('alice-content', <String, dynamic>{
      'method': 'getContent',
      'request': <String, dynamic>{'id': contentId, 'chapterId': chapter['id']},
    });
    expect(content['contentKind'], 'novel');
    expect((content['text'] as String).trim(), isNotEmpty);
  });
}
