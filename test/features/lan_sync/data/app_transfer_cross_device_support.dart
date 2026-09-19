/// OHOS 真机 App 包传输验收用的可观测平台边界。
///
/// 传输仍使用生产 [AppTransferSenderService] / [AppTransferReceiverConnection]；
/// 这里仅提供不会触碰真实安装器的测试包和安装确认记录。
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mg_read/features/lan_sync/application/app_update_service.dart';
import 'package:mg_read/features/lan_sync/domain/app_update_models.dart';

final class CrossDeviceOhosAppUpdateService implements AppUpdateService {
  CrossDeviceOhosAppUpdateService({required this.version, required List<int> packageBytes})
    : packageBytes = List<int>.unmodifiable(packageBytes),
      _root = Directory.systemTemp.createTempSync('mgread-ohos-app-transfer-');

  final AppVersionInfo version;
  final List<int> packageBytes;
  final Directory _root;
  bool permissionConfirmed = false;
  AppPackageDescriptor? launchedDescriptor;
  List<int>? installedBytes;

  @override
  Future<AppVersionInfo> currentVersion() async => version;

  @override
  Future<List<AppPackageOffer>> availablePackages() async => <AppPackageOffer>[AppPackageOffer(version: version, available: true)];

  @override
  Future<void> ensureInstallPermission() async {
    permissionConfirmed = true;
  }

  @override
  Future<PreparedAppPackage> preparePackage(AppUpdatePlatform platform) async {
    if (platform != AppUpdatePlatform.ohos) throw StateError('cross_device_ohos_platform_mismatch');
    final file = File('${_root.path}${Platform.pathSeparator}${version.version}-entry.hap');
    await file.writeAsBytes(packageBytes, flush: true);
    return PreparedAppPackage(
      descriptor: AppPackageDescriptor(
        version: version,
        packageName: 'com.ohos.mgread',
        bytes: packageBytes.length,
        checksum: sha256.convert(packageBytes).toString(),
        fileName: file.uri.pathSegments.last,
      ),
      file: file,
    );
  }

  @override
  Future<void> launchInstaller(File package, AppPackageDescriptor descriptor) async {
    if (!permissionConfirmed) throw StateError('cross_device_user_confirmation_required');
    launchedDescriptor = descriptor;
    installedBytes = await package.readAsBytes();
  }

  Future<void> close() async {
    if (await _root.exists()) await _root.delete(recursive: true);
  }
}

List<int> crossDeviceOhosAppBytes() => <int>[...List<int>.generate(256 * 1024, (index) => (index * 17 + 31) % 251), 0x48, 0x41, 0x50];
