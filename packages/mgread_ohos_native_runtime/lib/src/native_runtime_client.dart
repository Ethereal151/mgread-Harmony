import 'package:flutter/services.dart';

/// Narrow MethodChannel facade reserved for the staged OHOS native module.
///
/// The main app does not construct this client while using the default Node
/// engine. Keeping the channel here prevents Rust/C++ details from leaking
/// into the shared PluginRuntime API.
final class OhosNativeRuntimeClient {
  OhosNativeRuntimeClient({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('mgread_ohos_native_runtime');

  final MethodChannel _channel;

  Future<String> version() async => await _channel.invokeMethod<String>('version') ?? '';

  Future<int> create(String configJson) async =>
      await _channel.invokeMethod<int>('create', <String, Object?>{'configJson': configJson}) ?? -1;

  Future<int> start() async => await _channel.invokeMethod<int>('start') ?? -1;

  Future<String> invoke(String requestJson) async =>
      await _channel.invokeMethod<String>('invoke', <String, Object?>{'requestJson': requestJson}) ?? '';

  Future<String> lastError() async => await _channel.invokeMethod<String>('lastError') ?? '';

  Future<int> cancel(String requestId) async => await _channel.invokeMethod<int>('cancel', <String, Object?>{'requestId': requestId}) ?? -1;

  Future<int> stop() async => await _channel.invokeMethod<int>('stop') ?? -1;

  Future<int> restart() async => await _channel.invokeMethod<int>('restart') ?? -1;

  Future<String> hostStart({required String token, bool testMode = false}) async =>
      await _channel.invokeMethod<String>('hostStart', <String, Object?>{
        'token': token,
        'testMode': testMode,
      }) ??
      '';

  Future<int> hostStop() async => await _channel.invokeMethod<int>('hostStop') ?? -1;
}
