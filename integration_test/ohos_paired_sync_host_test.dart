/// OHOS 端跨设备配对同步 Host，供 Android/Windows 发起方验收。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mg_read/features/lan_sync/data/paired_sync_transport.dart';
import 'package:mg_read/features/lan_sync/domain/paired_device_models.dart';

import '../test/features/lan_sync/data/paired_sync_cross_device_support.dart';

const String _peerPlatform = String.fromEnvironment('MGREAD_CROSS_DEVICE_PEER', defaultValue: 'android');
const int _expectedRemotePlugins = int.fromEnvironment('MGREAD_CROSS_DEVICE_EXPECTED_REMOTE_PLUGINS', defaultValue: 1);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS host completes bidirectional HTTP sync with the selected peer', (tester) async {
    final (peerIdentity, peerPlatform) = switch (_peerPlatform) {
      'android' => (crossDeviceAndroidIdentity, PairedDevicePlatform.android),
      'windows' => (crossDeviceWindowsIdentity, PairedDevicePlatform.windows),
      'ohos' => (crossDeviceOhosPeerIdentity, PairedDevicePlatform.ohos),
      _ => throw StateError('unsupported_cross_device_peer'),
    };
    final gateway = CrossDeviceSyncGateway(side: 'ohos', pluginIds: const <String>['org.example.ohos.one']);
    final result = Completer<PairedSyncRunSummary>();
    final host = await PairedSyncHost.start(
      identity: crossDeviceOhosIdentity,
      devices: CrossDevicePairedRepository(crossDevicePeer(peerIdentity, peerPlatform)),
      identityStore: CrossDeviceIdentityStore(crossDeviceOhosIdentity, peerIdentity.deviceId),
      discoveryPort: 0,
      onIncoming: (session) async {
        try {
          result.complete(await session.run(gateway: gateway));
        } on Object catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        }
      },
    );
    addTearDown(host.close);
    debugPrint('MGREAD_CROSS_DEVICE_PORT=${host.port}');

    final summary = await result.future.timeout(const Duration(minutes: 6));

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
    debugPrint('MGREAD_CROSS_DEVICE_OHOS_SUCCESS=true');
  }, timeout: const Timeout(Duration(minutes: 7)));
}
