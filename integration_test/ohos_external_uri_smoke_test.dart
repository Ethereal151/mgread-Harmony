import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS dispatches an HTTPS external URI through the system bridge', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    expect(await OhosSystemClient.openUri(Uri.parse('https://example.com/')), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
