import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class ReaderPlatform extends PlatformInterface {
  ReaderPlatform() : super(token: _token);

  static final Object _token = Object();
  static ReaderPlatform _instance = MethodChannelReaderPlatform();

  static ReaderPlatform get instance => _instance;

  static set instance(ReaderPlatform value) {
    PlatformInterface.verifyToken(value, _token);
    _instance = value;
  }

  /// Private platform capability result. Unsupported platforms never receive a channel call.
  Future<ReaderPlatformCapabilities> capabilities() async =>
      const ReaderPlatformCapabilities();

  Future<void> setReaderSystemUi({
    required bool keepScreenOn,
    required bool immersiveMode,
    bool allowScreenDimming = false,
  }) {
    throw UnimplementedError('setReaderSystemUi() has not been implemented.');
  }

  /// Enables the host's native volume-key interception while a reader is
  /// actively accepting page-turn shortcuts.
  ///
  /// Hosts without a native reader bridge can keep the default no-op. The
  /// Flutter keyboard path still handles desktop and hardware-key events.
  Future<void> setVolumeKeyPageTurningEnabled(bool enabled) async {}

  bool get supportsKeepScreenOn => false;

  /// Volume keys intercepted by a native host reader bridge.
  static Stream<ReaderVolumeKey> get volumeKeyEvents =>
      MethodChannelReaderPlatform.volumeKeyEvents;

  /// Compatibility shorthand for existing platform fakes and clients.
  Future<void> setKeepScreenOn(bool enabled) =>
      setReaderSystemUi(keepScreenOn: enabled, immersiveMode: false);
}

@immutable
class ReaderPlatformCapabilities {
  const ReaderPlatformCapabilities({
    this.keepScreenOn = false,
    this.immersiveMode = false,
  });
  final bool keepScreenOn;
  final bool immersiveMode;
}

class MethodChannelReaderPlatform extends ReaderPlatform {
  static const MethodChannel _channel = MethodChannel('novel_reader_ui/system');
  static final StreamController<ReaderVolumeKey> _volumeKeyController =
      StreamController<ReaderVolumeKey>.broadcast();

  MethodChannelReaderPlatform() {
    _channel.setMethodCallHandler(_handleInputMethodCall);
  }

  static Stream<ReaderVolumeKey> get volumeKeyEvents =>
      _volumeKeyController.stream;

  static Future<void> _handleInputMethodCall(MethodCall call) async {
    if (call.method != 'volumeKey') return;
    final Object? rawDirection = call.arguments is Map
        ? (call.arguments as Map<Object?, Object?>)['direction']
        : call.arguments;
    final ReaderVolumeKey? direction = switch (rawDirection) {
      'up' => ReaderVolumeKey.up,
      'down' => ReaderVolumeKey.down,
      _ => null,
    };
    if (direction != null) _volumeKeyController.add(direction);
  }

  @override
  bool get supportsKeepScreenOn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  Future<ReaderPlatformCapabilities> capabilities() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.windows)) {
      return const ReaderPlatformCapabilities();
    }
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>('getCapabilities');
    return ReaderPlatformCapabilities(
      keepScreenOn: result?['keepScreenOn'] == true,
      immersiveMode: result?['immersiveMode'] == true,
    );
  }

  @override
  Future<void> setReaderSystemUi({
    required bool keepScreenOn,
    required bool immersiveMode,
    bool allowScreenDimming = false,
  }) {
    return _channel.invokeMethod<void>('setReaderSystemUi', <String, bool>{
      'keepScreenOn': keepScreenOn,
      'immersiveMode': immersiveMode,
      'allowScreenDimming': allowScreenDimming,
    });
  }

  @override
  Future<void> setVolumeKeyPageTurningEnabled(bool enabled) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<void>.value();
    }
    return _channel.invokeMethod<void>('setVolumeKeyPageTurningEnabled', {
      'enabled': enabled,
    });
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) =>
      setReaderSystemUi(keepScreenOn: enabled, immersiveMode: false);
}

enum ReaderVolumeKey { up, down }
