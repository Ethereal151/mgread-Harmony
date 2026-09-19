/// OHOS App 包传输接收端，验证校验和、用户确认入口及安装交接。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mg_read/features/lan_sync/data/app_transfer_transport.dart';
import 'package:mg_read/features/lan_sync/domain/app_transfer_qr_payload.dart';
import 'package:mg_read/features/lan_sync/domain/app_update_models.dart';

import '../test/features/lan_sync/data/app_transfer_cross_device_support.dart';

const String _senderAddress = String.fromEnvironment('MGREAD_APP_TRANSFER_ADDRESS');
const int _senderPort = int.fromEnvironment('MGREAD_APP_TRANSFER_PORT');
const String _senderSessionId = String.fromEnvironment('MGREAD_APP_TRANSFER_SESSION_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS receives, verifies, and hands a HAP package to the user-confirmed installer boundary', (tester) async {
    expect(_senderAddress, isNotEmpty);
    expect(_senderPort, inInclusiveRange(1, 65535));
    expect(_senderSessionId, isNotEmpty);
    final service = CrossDeviceOhosAppUpdateService(
      version: const AppVersionInfo(platform: AppUpdatePlatform.ohos, version: '9.9.0', buildNumber: 990),
      packageBytes: const <int>[1],
    );
    addTearDown(service.close);
    final connection = await AppTransferReceiverConnection.connectAny(
      AppTransferConnectionOffer(sessionId: _senderSessionId, port: _senderPort, addresses: <String>[_senderAddress]),
      await service.currentVersion(),
    );
    addTearDown(connection.close);
    expect(connection.remoteOffer.version.displayVersion, '9.9.1 (991)');
    expect(connection.remoteOffer.version.platform, AppUpdatePlatform.ohos);

    await service.ensureInstallPermission();
    await connection.downloadAndInstall(service, await service.currentVersion(), force: false);

    expect(service.permissionConfirmed, isTrue);
    expect(service.launchedDescriptor?.checksum, isNotEmpty);
    expect(service.launchedDescriptor?.bytes, crossDeviceOhosAppBytes().length);
    expect(service.installedBytes, orderedEquals(crossDeviceOhosAppBytes()));
    debugPrint(
      jsonEncode(<String, Object?>{
        'result': true,
        'permissionConfirmed': service.permissionConfirmed,
        'bytes': service.installedBytes!.length,
        'checksum': service.launchedDescriptor!.checksum,
      }),
    );
  });
}
