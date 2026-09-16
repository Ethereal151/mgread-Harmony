/// Typed Flutter boundary for the native OHOS Scan Kit bridge.
library;

import 'package:flutter/services.dart';

final class OhosBarcodeScanner {
  OhosBarcodeScanner._();

  static final OhosBarcodeScanner instance = OhosBarcodeScanner._();

  static const MethodChannel _channel = MethodChannel('mgread/ohos_scanner');

  /// Opens the OHOS Scan Kit default UI and returns one decoded QR value.
  ///
  /// A canceled scan returns null. Permission, capability and framework
  /// failures are surfaced as [PlatformException] for the page to report.
  Future<String?> scan() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('scan');
    if (raw == null) return null;
    final value = raw['value'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Invalid OHOS Scan Kit result.');
    }
    return value;
  }
}
