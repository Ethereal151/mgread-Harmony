/// Typed Flutter boundary for the native OHOS AVPlayer host.
library;

import 'dart:async';

import 'package:flutter/services.dart';

final class OhosMediaOpenResult {
  const OhosMediaOpenResult({
    required this.sessionId,
    this.textureId,
    this.duration,
  });

  final String sessionId;
  final int? textureId;
  final Duration? duration;
}

final class OhosMediaEvent {
  const OhosMediaEvent({
    required this.sessionId,
    required this.kind,
    this.value,
    this.message,
  });

  final String sessionId;
  final String kind;
  final Object? value;
  final String? message;
}

/// One process-scoped channel owner. Native AVPlayer objects never cross this
/// boundary; only immutable command payloads and state events do.
final class OhosMediaClient {
  OhosMediaClient._();

  static final OhosMediaClient instance = OhosMediaClient._();

  static const MethodChannel _methods = MethodChannel('mgread/ohos_media');
  static const EventChannel _events = EventChannel('mgread/ohos_media/events');

  Stream<OhosMediaEvent>? _eventStream;

  Stream<OhosMediaEvent> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .where((raw) => raw is Map)
      .cast<Map>()
      .map((raw) {
        final map = raw.cast<Object?, Object?>();
        final sessionId = map['sessionId'];
        final kind = map['kind'];
        if (sessionId is! String || kind is! String) {
          throw const FormatException('Invalid OHOS media event.');
        }
        return OhosMediaEvent(
          sessionId: sessionId,
          kind: kind,
          value: map['value'],
          message: map['message'] as String?,
        );
      });

  Future<OhosMediaOpenResult> openAudio({
    required String sessionId,
    required Uri uri,
    required Map<String, String> headers,
    required Duration initialPosition,
    required bool play,
    bool loop = false,
    String? trackId,
    String? title,
    String? artist,
    String? queueTitle,
    Uri? artwork,
  }) => _open('audio.open', <String, Object?>{
    'sessionId': sessionId,
    'url': uri.toString(),
    'headers': headers,
    'initialPositionMs': initialPosition.inMilliseconds,
    'play': play,
    'loop': loop,
    if (trackId != null) 'trackId': trackId,
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
    if (queueTitle != null) 'queueTitle': queueTitle,
    if (artwork != null) 'artworkUrl': artwork.toString(),
  });

  Future<OhosMediaOpenResult> openVideo({
    required String sessionId,
    required Uri uri,
    required Map<String, String> headers,
    String resourceType = 'video',
    required Duration initialPosition,
    required bool play,
    bool loop = false,
  }) => _open('video.open', <String, Object?>{
    'sessionId': sessionId,
    'url': uri.toString(),
    'headers': headers,
    'resourceType': resourceType,
    'initialPositionMs': initialPosition.inMilliseconds,
    'play': play,
    'loop': loop,
  });

  Future<OhosMediaOpenResult> _open(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
      method,
      arguments,
    );
    if (raw == null || raw['sessionId'] is! String) {
      throw const FormatException('Invalid OHOS media open response.');
    }
    final durationMs = raw['durationMs'];
    final textureId = raw['textureId'];
    return OhosMediaOpenResult(
      sessionId: raw['sessionId'] as String,
      textureId: textureId is int ? textureId : null,
      duration: durationMs is int && durationMs >= 0
          ? Duration(milliseconds: durationMs)
          : null,
    );
  }

  Future<void> command(
    String method,
    String sessionId, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) => _methods.invokeMethod<void>(method, <String, Object?>{
    'sessionId': sessionId,
    ...arguments,
  });
}
