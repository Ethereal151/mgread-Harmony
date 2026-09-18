import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

Future<void> _pumpUntilComplete(WidgetTester tester, Future<void> request) async {
  var complete = false;
  final tracked = request.whenComplete(() => complete = true);
  for (var index = 0; index < 100 && !complete; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tracked;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS browser session opens, navigates and reads HTML', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    await tester.pumpWidget(const MaterialApp(home: OhosBrowserSessionSurface()));
    await tester.pump();

    final host = OhosBrowserSessionHost();
    addTearDown(host.dispose);
    const pluginId = 'org.mgread.browser-smoke';
    const pluginName = 'browser-smoke';
    int deadline() => DateTime.now().millisecondsSinceEpoch + 15_000;

    await _pumpUntilComplete(
      tester,
      host
          .request(
            jobId: 'browser-smoke-open',
            deadlineUnixMs: deadline(),
            raw: const <String, Object?>{'pluginId': pluginId, 'pluginName': pluginName, 'operation': 'page.open', 'visible': false},
          )
          .then((_) {}),
    );
    await host.request(
      jobId: 'browser-smoke-navigate',
      deadlineUnixMs: deadline(),
      raw: const <String, Object?>{'pluginId': pluginId, 'pluginName': pluginName, 'operation': 'page.navigate', 'url': 'about:blank'},
    );
    final html = await host.request(
      jobId: 'browser-smoke-html',
      deadlineUnixMs: deadline(),
      raw: const <String, Object?>{'pluginId': pluginId, 'pluginName': pluginName, 'operation': 'page.html'},
    );
    expect(html['html'], isA<String>());
  });
}
