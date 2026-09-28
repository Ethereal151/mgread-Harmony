import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS dispatches a packaged file to the system share surface', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final runtimeProbe = (await OhosSystemClient.getCapabilitySnapshot())['supportsOhosRuntime'];
    final isX64OpenHarmony = runtimeProbe?.architecture.contains('x86') ?? false;

    final directory = await Directory.systemTemp.createTemp('mg-read-ohos-share-');
    final file = File('${directory.path}/share-smoke.mgread');
    await file.writeAsBytes(<int>[0x4D, 0x47, 0x52, 0x44]);
    addTearDown(() => directory.delete(recursive: true));

    // The OpenHarmony x64 image has no ACTION_SEND_DATA receiver. The native
    // bridge reports that capability boundary as false; arm64 HarmonyOS
    // devices with the system share surface must return true.
    expect(await OhosSystemClient.shareFile(file.path), isX64OpenHarmony ? isFalse : isTrue);
    await tester.pump(const Duration(milliseconds: 500));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
