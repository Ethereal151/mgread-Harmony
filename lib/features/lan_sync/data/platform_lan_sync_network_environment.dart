/// 局域网同步的真实平台网络判定。
///
/// Android 通过无运行时授权的系统网络能力查询确认 Wi-Fi；桌面以过滤后的私有 IPv4
/// 接口作为可用局域网依据。查询失败按不可用处理，避免在移动网络上盲目广播。
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:mg_read/features/lan_sync/application/lan_sync_network_environment.dart';
import 'package:mg_read/features/lan_sync/data/lan_sync_transport.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';

typedef AndroidWifiStatusResolver = Future<bool?> Function();
typedef LanSyncAddressResolver = Future<List<String>> Function();

final class PlatformLanSyncNetworkEnvironment implements LanSyncNetworkEnvironment, LanSyncNetworkEvents {
  PlatformLanSyncNetworkEnvironment({
    bool? requiresAndroidWifi,
    bool? requiresOhosNetwork,
    AndroidWifiStatusResolver? androidWifiStatusResolver,
    AndroidWifiStatusResolver? ohosNetworkStatusResolver,
    LanSyncAddressResolver? addressResolver,
  }) : _requiresAndroidWifi = requiresAndroidWifi ?? Platform.isAndroid,
       _requiresOhosNetwork = requiresOhosNetwork ?? Platform.operatingSystem == 'ohos',
       _androidWifiStatusResolver = androidWifiStatusResolver ?? _readAndroidWifiStatus,
       _ohosNetworkStatusResolver = ohosNetworkStatusResolver ?? _readOhosNetworkStatus,
       _addressResolver = addressResolver ?? eligibleLanSyncAddresses;

  final bool _requiresAndroidWifi;
  final bool _requiresOhosNetwork;
  final AndroidWifiStatusResolver _androidWifiStatusResolver;
  final AndroidWifiStatusResolver _ohosNetworkStatusResolver;
  final LanSyncAddressResolver _addressResolver;

  @override
  Stream<bool> get availabilityChanges => _requiresOhosNetwork ? _ohosNetworkChanges : const Stream<bool>.empty();

  @override
  Future<bool> isLocalNetworkAvailable() async {
    try {
      if (_requiresAndroidWifi) return await _androidWifiStatusResolver() ?? false;
      if (_requiresOhosNetwork) {
        final nativeAvailable = await _ohosNetworkStatusResolver() ?? false;
        return nativeAvailable && (await _addressResolver()).isNotEmpty;
      }
      return (await _addressResolver()).isNotEmpty;
    } on Object {
      return false;
    }
  }
}

const MethodChannel _networkEnvironmentChannel = MethodChannel('mgread/network_environment');
const EventChannel _networkEnvironmentEvents = EventChannel('mgread/network_environment/events');

Future<bool?> _readAndroidWifiStatus() => _networkEnvironmentChannel.invokeMethod<bool>('isWifiConnected');

Future<bool?> _readOhosNetworkStatus() async => (await OhosSystemClient.getLocalNetworkAddresses()).isNotEmpty;

Stream<bool> get _ohosNetworkChanges => _networkEnvironmentEvents.receiveBroadcastStream().where((value) => value is bool).cast<bool>();
