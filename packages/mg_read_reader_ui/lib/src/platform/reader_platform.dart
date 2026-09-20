import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Applies the route-scoped video window mode on platforms that expose a
  /// native window owner. The default keeps older hosts source-compatible.
  Future<void> setVideoWindowMode({required bool fullscreen}) =>
      Future<void>.value();

  /// Enables the host's native volume-key interception while a reader is
  /// actively accepting page-turn shortcuts.
  Future<void> setVolumeKeyPageTurningEnabled(bool enabled) async {}

  /// Whether this host can override the application's screen brightness.
  bool get supportsApplicationBrightness => false;

  /// Sets the application's display brightness for the active reader route.
  Future<void> setApplicationBrightness(double brightness) async {}

  /// Releases the application's display brightness override.
  Future<void> resetApplicationBrightness() async {}

  bool get supportsKeepScreenOn => false;

  /// Opens a source-owned URL in the platform browser.
  Future<bool> openExternalUrl(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

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
    this.volumeKeyPageTurning = true,
  });

  final bool keepScreenOn;
  final bool immersiveMode;

  /// Whether the host can expose physical volume keys as page-turn shortcuts.
  /// Older hosts default to true for source compatibility.
  final bool volumeKeyPageTurning;
}

class MethodChannelReaderPlatform extends ReaderPlatform {
  static const MethodChannel _channel = MethodChannel('novel_reader_ui/system');
  static const MethodChannel _systemChannel = MethodChannel(
    'mgread/ohos_system',
  );
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

  bool get _isOhos => !kIsWeb && Platform.operatingSystem == 'ohos';

  @override
  bool get supportsKeepScreenOn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows ||
          _isOhos);

  @override
  bool get supportsApplicationBrightness =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows ||
          _isOhos);

  @override
  Future<bool> openExternalUrl(Uri uri) async {
    if (_isOhos) {
      return await _systemChannel.invokeMethod<bool>(
            'openUri',
            <String, Object>{'uri': uri.toString()},
          ) ??
          false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<ReaderPlatformCapabilities> capabilities() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.windows &&
            !_isOhos)) {
      return const ReaderPlatformCapabilities();
    }
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>('getCapabilities');
    return ReaderPlatformCapabilities(
      keepScreenOn: result?['keepScreenOn'] == true,
      immersiveMode: result?['immersiveMode'] == true,
      volumeKeyPageTurning: result?['volumeKeyPageTurning'] != false,
    );
  }

  @override
  Future<void> setReaderSystemUi({
    required bool keepScreenOn,
    required bool immersiveMode,
    bool allowScreenDimming = false,
  }) => _channel.invokeMethod<void>('setReaderSystemUi', <String, bool>{
    'keepScreenOn': keepScreenOn,
    'immersiveMode': immersiveMode,
    'allowScreenDimming': allowScreenDimming,
  });

  @override
  Future<void> setVideoWindowMode({required bool fullscreen}) {
    if (!_isOhos) return Future<void>.value();
    return _channel.invokeMethod<void>('setVideoWindowMode', <String, bool>{
      'fullscreen': fullscreen,
    });
  }

  @override
  Future<void> setVolumeKeyPageTurningEnabled(bool enabled) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<void>.value();
    }
    return _channel.invokeMethod<void>(
      'setVolumeKeyPageTurningEnabled',
      <String, bool>{'enabled': enabled},
    );
  }

  @override
  Future<void> setApplicationBrightness(double brightness) => ScreenBrightness
      .instance
      .setApplicationScreenBrightness(brightness.clamp(0.05, 1).toDouble());

  @override
  Future<void> resetApplicationBrightness() =>
      ScreenBrightness.instance.resetApplicationScreenBrightness();

  @override
  Future<void> setKeepScreenOn(bool enabled) =>
      setReaderSystemUi(keepScreenOn: enabled, immersiveMode: false);
}

enum ReaderVolumeKey { up, down }
