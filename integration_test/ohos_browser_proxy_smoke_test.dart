import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

Future<T> _pumpUntilComplete<T>(WidgetTester tester, Future<T> request) async {
  var complete = false;
  final tracked = request.whenComplete(() => complete = true);
  for (var index = 0; index < 200 && !complete; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return tracked;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS ArkWeb routes a LAN HTTP page through the custom proxy', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    await tester.pumpWidget(const MaterialApp(home: OhosBrowserSessionSurface()));
    await tester.pump();

    final addresses = await OhosSystemClient.getLocalNetworkAddresses();
    final address = addresses.firstWhere((value) => value.trim().isNotEmpty);
    final host = OhosBrowserSessionHost();
    addTearDown(host.dispose);
    int deadline() => DateTime.now().millisecondsSinceEpoch + 20_000;
    const pluginId = 'org.mgread.ohos.proxy-smoke';
    await _pumpUntilComplete(
      tester,
      host.request(
        jobId: 'proxy-smoke-open',
        deadlineUnixMs: deadline(),
        raw: const <String, Object?>{'pluginId': pluginId, 'pluginName': 'proxy-smoke', 'operation': 'page.open', 'visible': false},
      ),
    );

    final origin = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final proxy = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    addTearDown(() async {
      await OhosBrowserSessionHost.configureProxy(null);
      await origin.close(force: true);
      await proxy.close(force: true);
    });
    origin.listen((request) {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body>direct-origin</body></html>')
        ..close();
    });
    proxy.listen((request) {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body>custom-proxy-hit:${request.uri}</body></html>')
        ..close();
    });

    await OhosBrowserSessionHost.configureProxy(Uri(scheme: 'http', host: address, port: proxy.port));
    await _pumpUntilComplete(
      tester,
      host.request(
        jobId: 'proxy-smoke-navigate',
        deadlineUnixMs: deadline(),
        raw: <String, Object?>{
          'pluginId': pluginId,
          'pluginName': 'proxy-smoke',
          'operation': 'page.navigate',
          'url': 'http://$address:${origin.port}/proxy-check',
        },
      ),
    );
    final page = await _pumpUntilComplete(
      tester,
      host.request(
        jobId: 'proxy-smoke-html',
        deadlineUnixMs: deadline(),
        raw: const <String, Object?>{'pluginId': pluginId, 'pluginName': 'proxy-smoke', 'operation': 'page.html'},
      ),
    );
    expect(page['html'], contains('custom-proxy-hit'));
  });
}
