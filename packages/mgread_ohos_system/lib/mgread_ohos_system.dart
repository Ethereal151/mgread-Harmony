/// Small application-owned bridge for OHOS system UI, package, and LAN services.
library;

import 'dart:io';

import 'package:flutter/services.dart';

final class OhosSystemClient {
  OhosSystemClient._();

  static const MethodChannel _channel = MethodChannel('mgread/ohos_system');
  static const EventChannel _networkEvents = EventChannel('mgread/network_environment/events');

  static Future<String?> pickImportFile() => _channel.invokeMethod<String>('pickImportFile');

  /// Picks a Node data-source collection and copies it into the app cache so
  /// Flutter can validate the archive without retaining an external URI.
  static Future<String?> pickDataSourceCollection() => _channel.invokeMethod<String>('pickDataSourceCollection');

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
    final packageName = value['packageName'] as String?;
    final hapPath = value['hapPath'] as String?;
    if (version == null || version.trim().isEmpty || build == null || packageName == null || packageName.trim().isEmpty) return null;
    return OhosPackageInfo(
      version: version,
      build: build,
      packageName: packageName,
      hapPath: hapPath?.trim().isEmpty == true ? null : hapPath?.trim(),
    );
  }

  static Future<OhosDeviceInfo?> getDeviceInfo() async {
    final value = await _channel.invokeMethod<Object?>('getDeviceInfo');
    if (value is! Map) return null;
    final model = value['model'];
    final label = value['label'];
    if (model is! String || model.trim().isEmpty || label is! String || label.trim().isEmpty) return null;
    return OhosDeviceInfo(model: model, label: label);
  }

  /// Returns the current UIAbility files directory from the OHOS context.
  ///
  /// The path is owned by the platform sandbox and must not be reconstructed
  /// from a hard-coded `/data` layout in Dart.
  static Future<Directory?> getFilesDirectory() async {
    final value = await _channel.invokeMethod<Object?>('getFilesDirectory');
    if (value is! String || value.trim().isEmpty) return null;
    return Directory(value.trim());
  }

  static Future<List<String>> getLocalNetworkAddresses() async {
    final value = await _channel.invokeMethod<Object?>('getLocalNetworkAddresses');
    if (value is! List) return const <String>[];
    return List<String>.unmodifiable(value.whereType<String>());
  }

  /// Whether Network Kit currently exposes a Wi-Fi/Ethernet local address.
  static Future<bool> isLocalNetworkAvailable() async => await _channel.invokeMethod<bool>('isLocalNetworkAvailable') ?? false;

  /// Emits the current LAN availability after Network Kit transitions.
  static Stream<bool> get localNetworkAvailabilityChanges =>
      _networkEvents.receiveBroadcastStream().where((value) => value is bool).cast<bool>();

  /// Returns native OHOS capability probes. The application owns the public
  /// immutable snapshot model; this package only validates the channel shape.
  static Future<Map<String, OhosCapabilityProbe>> getCapabilitySnapshot() async {
    final value = await _channel.invokeMethod<Object?>('getCapabilities');
    if (value is! Map) return const <String, OhosCapabilityProbe>{};
    final result = <String, OhosCapabilityProbe>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final map = entry.value as Map;
      final available = map['available'];
      final reason = map['reason'];
      final apiVersion = map['apiVersion'];
      final architecture = map['architecture'];
      if (available is! bool || reason is! String || apiVersion is! String || architecture is! String) continue;
      result[entry.key as String] = OhosCapabilityProbe(
        available: available,
        reason: reason,
        apiVersion: apiVersion,
        architecture: architecture,
      );
    }
    return Map<String, OhosCapabilityProbe>.unmodifiable(result);
  }
}

final class OhosPackageInfo {
  const OhosPackageInfo({required this.version, required this.build, required this.packageName, this.hapPath});

  final String version;
  final int build;
  final String packageName;
  final String? hapPath;
}

final class OhosDeviceInfo {
  const OhosDeviceInfo({required this.model, required this.label});

  final String model;
  final String label;
}

final class OhosCapabilityProbe {
  const OhosCapabilityProbe({required this.available, required this.reason, required this.apiVersion, required this.architecture});

  final bool available;
  final String reason;
  final String apiVersion;
  final String architecture;
}
