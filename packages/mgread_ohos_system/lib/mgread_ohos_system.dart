/// Small application-owned bridge for OHOS system UI and package services.
library;

import 'package:flutter/services.dart';

final class OhosSystemClient {
  OhosSystemClient._();

  static const MethodChannel _channel = MethodChannel('mgread/ohos_system');

  static Future<String?> pickImportFile() => _channel.invokeMethod<String>('pickImportFile');

  static Future<bool> exportFile({required String path, required String suggestedName}) async {
    return await _channel.invokeMethod<bool>('exportFile', <String, Object>{'path': path, 'suggestedName': suggestedName}) ?? false;
  }

  static Future<bool> shareFile(String path) async {
    return await _channel.invokeMethod<bool>('shareFile', <String, Object>{'path': path}) ?? false;
  }

  static Future<bool> openUri(Uri uri) async {
    return await _channel.invokeMethod<bool>('openUri', <String, Object>{'uri': uri.toString()}) ?? false;
  }

  static Future<OhosPackageInfo?> getPackageInfo() async {
    final value = await _channel.invokeMethod<Object?>('getPackageInfo');
    if (value is! Map) return null;
    final version = value['version'] as String?;
    final build = value['build'] as int?;
    if (version == null || version.trim().isEmpty || build == null) return null;
    return OhosPackageInfo(version: version, build: build);
  }
}

final class OhosPackageInfo {
  const OhosPackageInfo({required this.version, required this.build});

  final String version;
  final int build;
}
