import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/lan_sync/application/device_sync_controller.dart';
import 'package:mg_read/features/lan_sync/domain/lan_pairing_payload.dart';
import 'package:mg_read/features/lan_sync/presentation/paired_device_widgets.dart';

void main() {
  testWidgets('pairing failure shows its real transport code instead of claiming a LAN mismatch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DevicePairingSheet(
            state: const DeviceSyncState(
              pairingPhase: DevicePairingPhase.failed,
              lastErrorCode: 'lan_sync_http_failed',
              lastErrorDetails: '错误类型：LanSyncTransportException\n技术原因：status_502',
            ),
            onBeginPairing: () {},
            onApprovePairing: () {},
            onRejectPairing: () {},
            onCancelPairing: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('局域网 HTTP 连接'), findsOneWidget);
    expect(find.byKey(const Key('device-pairing-error-details')), findsOneWidget);
    expect(find.textContaining('status_502'), findsOneWidget);
    expect(find.textContaining('确认两台设备在同一局域网'), findsNothing);
  });

  testWidgets('pairing sheet displays the QR immediately without a second action', (tester) async {
    final offer = LanPairingOffer(
      addresses: const <String>['192.168.1.10'],
      deviceId: 'desktop_device_123456',
      label: '开发电脑',
      port: 12345,
      secret: List<int>.filled(32, 1),
      sessionId: 'pairing_session_123456',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DevicePairingSheet(
            state: DeviceSyncState(pairingPhase: DevicePairingPhase.showingOffer, pairingOffer: offer),
            onBeginPairing: () {},
            onApprovePairing: () {},
            onRejectPairing: () {},
            onCancelPairing: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('device-sync-pairing-qr')), findsOneWidget);
    expect(find.byKey(const Key('device-sync-show-pairing-code')), findsNothing);
  });
}
