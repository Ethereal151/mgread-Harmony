/// Android 端向 OHOS 发起跨设备配对同步验收。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mg_read/features/lan_sync/data/paired_sync_transport.dart';
import 'package:mg_read/features/lan_sync/domain/paired_device_models.dart';

import '../test/features/lan_sync/data/paired_sync_cross_device_support.dart';

const String _ohosAddress = String.fromEnvironment('MGREAD_CROSS_DEVICE_ADDRESS');
const int _ohosPort = int.fromEnvironment('MGREAD_CROSS_DEVICE_PORT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android completes bidirectional HTTP sync with OHOS', (tester) async {
    expect(_ohosAddress, isNotEmpty);
    expect(_ohosPort, inInclusiveRange(1, 65535));
    final gateway = CrossDeviceSyncGateway(side: 'android', pluginIds: const <String>['org.example.android.one']);
    final session = await PairedSyncClientSession.connectAny(
      endpoints: <PairedSyncEndpoint>[
        PairedSyncEndpoint(
          address: _ohosAddress,
          deviceId: crossDeviceOhosIdentity.deviceId,
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 2)),
          label: crossDeviceOhosIdentity.label,
          port: _ohosPort,
        ),
      ],
      identity: crossDeviceAndroidIdentity,
      peer: crossDevicePeer(crossDeviceOhosIdentity, PairedDevicePlatform.ohos),
      sharedSecret: crossDeviceSecret(),
    );

    final summary = await session.run(gateway: gateway);

    expect(summary.receivedBooks, 1);
    expect(summary.receivedPlugins, 1);
    expect(summary.sentBooks, 1);
    expect(summary.sentPlugins, 1);
    expect(gateway.appliedShelfItems.single.remoteContentId, 'ohos-book');
    expect(gateway.importedPluginIds, <String>{'org.example.ohos.one'});
  });
}
