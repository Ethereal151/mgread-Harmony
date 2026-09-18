import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/features/lan_sync/data/platform_lan_sync_network_environment.dart';

void main() {
  test('Android permits LAN sync only when the platform reports Wi-Fi', () async {
    final connected = PlatformLanSyncNetworkEnvironment(requiresAndroidWifi: true, androidWifiStatusResolver: () async => true);
    final disconnected = PlatformLanSyncNetworkEnvironment(requiresAndroidWifi: true, androidWifiStatusResolver: () async => false);

    expect(await connected.isLocalNetworkAvailable(), isTrue);
    expect(await disconnected.isLocalNetworkAvailable(), isFalse);
  });

  test('Android platform query failure disables LAN traffic', () async {
    final environment = PlatformLanSyncNetworkEnvironment(
      requiresAndroidWifi: true,
      androidWifiStatusResolver: () async => throw StateError('channel unavailable'),
    );

    expect(await environment.isLocalNetworkAvailable(), isFalse);
  });

  test('desktop requires at least one eligible private LAN address', () async {
    final connected = PlatformLanSyncNetworkEnvironment(
      requiresAndroidWifi: false,
      addressResolver: () async => const <String>['192.168.1.8'],
    );
    final disconnected = PlatformLanSyncNetworkEnvironment(requiresAndroidWifi: false, addressResolver: () async => const <String>[]);

    expect(await connected.isLocalNetworkAvailable(), isTrue);
    expect(await disconnected.isLocalNetworkAvailable(), isFalse);
  });

  test('OHOS requires Network Kit availability and a local address', () async {
    final connected = PlatformLanSyncNetworkEnvironment(
      requiresAndroidWifi: false,
      requiresOhosNetwork: true,
      ohosNetworkStatusResolver: () async => true,
      addressResolver: () async => const <String>['192.168.1.20'],
    );
    final cellularOnly = PlatformLanSyncNetworkEnvironment(
      requiresAndroidWifi: false,
      requiresOhosNetwork: true,
      ohosNetworkStatusResolver: () async => true,
      addressResolver: () async => const <String>[],
    );

    expect(await connected.isLocalNetworkAvailable(), isTrue);
    expect(await cellularOnly.isLocalNetworkAvailable(), isFalse);
  });
}
