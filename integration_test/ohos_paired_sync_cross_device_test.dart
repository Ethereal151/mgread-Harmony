/// OHOS 端跨设备配对同步客户端。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mg_read/features/lan_sync/data/paired_sync_transport.dart';
import 'package:mg_read/features/lan_sync/domain/paired_device_models.dart';

import '../test/features/lan_sync/data/paired_sync_cross_device_support.dart';

const String _peerAddress = String.fromEnvironment('MGREAD_CROSS_DEVICE_ADDRESS');
const int _peerPort = int.fromEnvironment('MGREAD_CROSS_DEVICE_PORT');
const String _peerPlatform = String.fromEnvironment('MGREAD_CROSS_DEVICE_PLATFORM', defaultValue: 'windows');
const int _expectedRemotePlugins = int.fromEnvironment('MGREAD_CROSS_DEVICE_EXPECTED_REMOTE_PLUGINS', defaultValue: 3);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS completes bidirectional HTTP sync with the selected peer', (tester) async {
    expect(_peerAddress, isNotEmpty);
    expect(_peerPort, inInclusiveRange(1, 65535));
    final (peerIdentity, peerPlatform) = switch (_peerPlatform) {
      'android' => (crossDeviceAndroidIdentity, PairedDevicePlatform.android),
      'windows' => (crossDeviceWindowsIdentity, PairedDevicePlatform.windows),
      'ohos' => (crossDeviceOhosPeerIdentity, PairedDevicePlatform.ohos),
      _ => throw StateError('unsupported_cross_device_peer'),
    };
    final gateway = CrossDeviceSyncGateway(side: 'ohos', pluginIds: const <String>['org.example.ohos.one']);
    final session = await PairedSyncClientSession.connectAny(
      endpoints: <PairedSyncEndpoint>[
        PairedSyncEndpoint(
          address: _peerAddress,
          deviceId: peerIdentity.deviceId,
          expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 2)),
          label: peerIdentity.label,
          port: _peerPort,
        ),
      ],
      identity: crossDeviceOhosIdentity,
      peer: crossDevicePeer(peerIdentity, peerPlatform),
      sharedSecret: crossDeviceSecret(),
    );

    final summary = await session.run(gateway: gateway);

    expect(summary.receivedBooks, 1);
    expect(summary.receivedPlugins, _expectedRemotePlugins);
    expect(summary.sentBooks, 1);
    expect(summary.sentPlugins, 1);
    final peerPrefix = switch (_peerPlatform) {
      'android' => 'android',
      'windows' => 'windows',
      'ohos' => 'ohos',
      _ => throw StateError('unsupported_cross_device_peer'),
    };
    expect(gateway.appliedShelfItems.single.remoteContentId, '$peerPrefix-book');
    expect(gateway.importedPluginIds, hasLength(_expectedRemotePlugins));
  });
}
