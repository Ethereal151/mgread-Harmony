/// OHOS App 包传输发送端，供第二台 OHOS 真机接收验收。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mg_read/features/lan_sync/data/app_transfer_transport.dart';
import 'package:mg_read/features/lan_sync/domain/app_update_models.dart';

import '../test/features/lan_sync/data/app_transfer_cross_device_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS serves an independently verified HAP package transfer', (tester) async {
    final service = CrossDeviceOhosAppUpdateService(
      version: const AppVersionInfo(platform: AppUpdatePlatform.ohos, version: '9.9.1', buildNumber: 991),
      packageBytes: crossDeviceOhosAppBytes(),
    );
    addTearDown(service.close);
    final sender = await AppTransferSenderService.start(service);
    addTearDown(sender.close);
    debugPrint(
      'MGREAD_OHOS_APP_TRANSFER_OFFER=${jsonEncode(<String, Object?>{'sessionId': sender.connectionOffer.sessionId, 'port': sender.connectionOffer.port, 'addresses': sender.connectionOffer.addresses})}',
    );
    debugPrint('MGREAD_OHOS_APP_TRANSFER_WAITING=true');
    await Future<void>.delayed(const Duration(minutes: 6));
  }, timeout: const Timeout(Duration(minutes: 7)));
}
