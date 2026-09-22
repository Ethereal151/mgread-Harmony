import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS document picker saves a backup file', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    final directory = await Directory.systemTemp.createTemp('mg-read-ohos-export-');
    final file = File('${directory.path}/picker-smoke.mgread');
    await file.writeAsBytes(<int>[0x4D, 0x47, 0x52, 0x45, 0x41, 0x44]);
    addTearDown(() => directory.delete(recursive: true));
    final saved = await OhosSystemClient.exportFile(path: file.path, suggestedName: 'picker-smoke.mgread');
    debugPrint('OHOS_FILE_EXPORT_RESULT=$saved');
    expect(saved, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('OHOS document picker returns a selected backup file', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    final path = await OhosSystemClient.pickImportFile();
    debugPrint('OHOS_FILE_PICKER_PATH=${path ?? '<cancelled>'}');
    expect(path, isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
