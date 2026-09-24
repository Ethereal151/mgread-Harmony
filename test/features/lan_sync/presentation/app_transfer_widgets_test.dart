import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/lan_sync/application/app_transfer_controller.dart';
import 'package:mg_read/features/lan_sync/domain/app_update_models.dart';
import 'package:mg_read/features/lan_sync/presentation/app_transfer_widgets.dart';

void main() {
  testWidgets('temporary App confirmation shows both versions and normal upgrade', (tester) async {
    const local = AppVersionInfo(platform: AppUpdatePlatform.android, version: '1.0.0', buildNumber: 10);
    const remote = AppVersionInfo(platform: AppUpdatePlatform.android, version: '1.1.0', buildNumber: 11);
    bool? forced;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppTransferPanel(
              state: const AppTransferState(
                phase: AppTransferPhase.ready,
                role: AppTransferRole.receiver,
                message: '请核对版本并确认安装',
                localVersion: local,
                offeredVersion: remote,
                pairingCode: '123456',
              ),
              onScanQr: () {},
              onInstall: (value) => forced = value,
              onCancel: () {},
              onReset: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('1.0.0 (10)'), findsOneWidget);
    expect(find.text('1.1.0 (11)'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-transfer-upgrade')));
    expect(forced, isFalse);
  });
}
