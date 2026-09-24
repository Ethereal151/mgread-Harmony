import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/lan_sync/application/app_update_service.dart';
import 'package:mg_read/features/lan_sync/application/device_identity_store.dart';
import 'package:mg_read/features/lan_sync/application/device_sync_controller.dart';
import 'package:mg_read/features/lan_sync/application/lan_sync_gateway.dart';
import 'package:mg_read/features/lan_sync/application/lan_sync_network_environment.dart';
import 'package:mg_read/features/lan_sync/application/paired_device_repository.dart';
import 'package:mg_read/features/lan_sync/domain/app_update_models.dart';
import 'package:mg_read/features/lan_sync/domain/lan_sync_models.dart';
import 'package:mg_read/features/lan_sync/domain/paired_device_models.dart';
import 'package:mg_read/features/lan_sync/presentation/lan_sync_page.dart';

void main() {
  const deviceId = 'desktop_device_123456';
  const localVersion = AppVersionInfo(platform: AppUpdatePlatform.windows, version: '2.0.0', buildNumber: 20);

  testWidgets('LanSyncPage dispatches manual paired-device pull and exposes push', (tester) async {
    final container = await _pumpPage(
      tester,
      DeviceSyncState(
        started: true,
        devices: <PairedDevice>[_device(deviceId)],
        onlineDeviceIds: const <String>{deviceId},
        localAppVersion: localVersion,
      ),
    );

    final pull = find.byKey(const Key('device-sync-pull-$deviceId'));
    final push = find.byKey(const Key('device-sync-push-$deviceId'));
    expect(tester.widget<OutlinedButton>(pull).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(push).onPressed, isNotNull);

    await tester.tap(pull);
    await tester.pumpAndSettle();

    expect(container.read(deviceSyncControllerProvider).lastErrorCode, 'lan_sync_local_network_unavailable');
    await _disposePage(tester, container);
  });

  testWidgets('LanSyncPage confirms paired App upgrade before dispatching install', (tester) async {
    final container = await _pumpPage(
      tester,
      DeviceSyncState(
        started: true,
        devices: <PairedDevice>[_device(deviceId)],
        onlineDeviceIds: const <String>{deviceId},
        localAppVersion: localVersion,
        appOffersByDeviceId: const <String, AppPackageOffer>{
          deviceId: AppPackageOffer(
            version: AppVersionInfo(platform: AppUpdatePlatform.windows, version: '2.1.0', buildNumber: 21),
            available: true,
          ),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('device-sync-app-upgrade-$deviceId')));
    await tester.pumpAndSettle();

    expect(find.text('从在线设备升级 App？'), findsOneWidget);
    expect(find.text('2.0.0 (20)'), findsOneWidget);
    expect(find.text('2.1.0 (21)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paired-app-update-confirm')));
    await tester.pumpAndSettle();

    expect(container.read(deviceSyncControllerProvider).lastErrorCode, 'lan_sync_peer_offline');
    await _disposePage(tester, container);
  });

  testWidgets('LanSyncPage requires explicit confirmation for same-version force install', (tester) async {
    final container = await _pumpPage(
      tester,
      DeviceSyncState(
        started: true,
        devices: <PairedDevice>[_device(deviceId)],
        onlineDeviceIds: const <String>{deviceId},
        localAppVersion: localVersion,
        appOffersByDeviceId: const <String, AppPackageOffer>{deviceId: AppPackageOffer(version: localVersion, available: true)},
      ),
    );

    await tester.tap(find.byKey(const Key('device-sync-app-force-$deviceId')));
    await tester.pumpAndSettle();

    expect(find.text('强制安装此版本？'), findsOneWidget);
    expect(find.byKey(const Key('paired-app-update-confirm')), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await _disposePage(tester, container);
  });

  testWidgets('all-devices sheet keeps actions for devices beyond the home-card limit', (tester) async {
    final devices = List<PairedDevice>.generate(4, (index) => _device('desktop_device_12345$index', label: '设备 ${index + 1}'));
    final container = await _pumpPage(
      tester,
      DeviceSyncState(
        started: true,
        devices: devices,
        onlineDeviceIds: devices.map((device) => device.deviceId).toSet(),
        localAppVersion: localVersion,
      ),
    );

    await tester.drag(find.byKey(const Key('lan-sync-content')), const Offset(0, -400));
    await tester.pumpAndSettle();
    final showAll = find.text('查看全部 4 台设备');
    await tester.tap(showAll);
    await tester.pumpAndSettle();

    final fourthPull = find.byKey(const Key('device-sync-pull-desktop_device_123453'));
    expect(fourthPull, findsOneWidget);
    expect(find.byKey(const Key('device-sync-push-desktop_device_123453')), findsOneWidget);
    await tester.ensureVisible(fourthPull);
    await _disposePage(tester, container);
  });
}

Future<ProviderContainer> _pumpPage(WidgetTester tester, DeviceSyncState initialState) async {
  final localVersion = initialState.localAppVersion!;
  final container = ProviderContainer(
    overrides: [
      deviceSyncControllerProvider.overrideWithBuild((ref, notifier) => initialState),
      pairedDeviceRepositoryProvider.overrideWithValue(_Repository(initialState.devices)),
      deviceIdentityStoreProvider.overrideWithValue(const _IdentityStore()),
      lanSyncNetworkEnvironmentProvider.overrideWithValue(const _OfflineNetwork()),
      lanSyncGatewayProvider.overrideWithValue(const _Gateway()),
      appUpdateServiceProvider.overrideWithValue(_AppUpdateService(localVersion)),
    ],
  );
  addTearDown(() async {
    await container.read(deviceSyncControllerProvider.notifier).stop();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: LanSyncPage(onBackRequested: () {}, onDestinationRequested: (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _disposePage(WidgetTester tester, ProviderContainer container) async {
  await container.read(deviceSyncControllerProvider.notifier).stop();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

PairedDevice _device(String deviceId, {String label = '开发电脑'}) => PairedDevice(
  autoSync: true,
  createdAtUtc: DateTime.utc(2026, 9, 22),
  deviceId: deviceId,
  label: label,
  mode: PairedSyncMode.bidirectional,
  platform: PairedDevicePlatform.windows,
  syncBookshelf: true,
  syncPlugins: true,
);

final class _Repository implements PairedDeviceRepository {
  const _Repository(this.devices);

  final List<PairedDevice> devices;

  @override
  Future<List<PairedDevice>> list() async => devices;

  @override
  Future<PairedDevice?> read(String deviceId) async {
    for (final device in devices) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }

  @override
  Future<void> remove(String deviceId) async {}

  @override
  Future<void> upsert(PairedDevice device) async {}
}

final class _IdentityStore implements DeviceIdentityStore {
  const _IdentityStore();

  @override
  Future<void> deletePeerSecret(String peerDeviceId) async {}

  @override
  Future<LocalDeviceIdentity> loadOrCreateIdentity() async => const LocalDeviceIdentity(deviceId: 'local_device_12345678', label: '本机');

  @override
  Future<List<int>?> readPeerSecret(String peerDeviceId) async => null;

  @override
  Future<void> writePeerSecret(String peerDeviceId, List<int> secret) async {}
}

final class _OfflineNetwork implements LanSyncNetworkEnvironment {
  const _OfflineNetwork();

  @override
  Future<bool> isLocalNetworkAvailable() async => false;
}

final class _AppUpdateService implements AppUpdateService {
  const _AppUpdateService(this.version);

  final AppVersionInfo version;

  @override
  Future<AppVersionInfo> currentVersion() async => version;

  @override
  Future<List<AppPackageOffer>> availablePackages() async => const <AppPackageOffer>[];

  @override
  Future<void> ensureInstallPermission() async {}

  @override
  Future<void> launchInstaller(File package, AppPackageDescriptor descriptor) async {}

  @override
  Future<PreparedAppPackage> preparePackage(AppUpdatePlatform platform) => throw UnimplementedError();
}

final class _Gateway implements LanSyncGateway {
  const _Gateway();

  @override
  Future<LanSyncManifest> createManifest() async =>
      const LanSyncManifest(plugins: <LanSyncPluginDescriptor>[], shelfItems: <LanSyncShelfItem>[], skippedShelfItems: 0);

  @override
  Future<void> cancelPluginImports() async {}

  @override
  Future<void> preparePluginImports(List<LanSyncPluginDescriptor> plugins, {Set<String> forceUpgradePluginIds = const <String>{}}) async {}

  @override
  Future<Stream<List<int>>> openPluginArchive(LanSyncPluginDescriptor plugin) async => const Stream<List<int>>.empty();

  @override
  Future<LanSyncImportPreview> previewImport(LanSyncManifest manifest, {bool force = false}) => throw UnimplementedError();

  @override
  Future<void> importPluginArchive(LanSyncPluginDescriptor plugin, Stream<List<int>> bytes) => throw UnimplementedError();

  @override
  Future<LanSyncPluginImportResult> finishPluginImports() => throw UnimplementedError();

  @override
  Future<LanSyncApplyResult> applyImport({
    required LanSyncManifest manifest,
    required Map<String, LanSyncConflictChoice> conflictChoices,
    required Set<String> availablePluginIds,
    required LanSyncPluginImportResult pluginResult,
    bool force = false,
  }) => throw UnimplementedError();
}
