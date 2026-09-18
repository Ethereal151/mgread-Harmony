/// OHOS owner for browser.session.v1.
///
/// ArkWeb is intentionally kept behind this narrow MethodChannel boundary.
/// Until the native ArkWeb host is registered, every operation returns the
/// stable `unsupported` code; it must never silently fall back to HTTP and
/// leak a source's Cookie/Profile state outside the Runtime session.
library;

import 'package:flutter/services.dart';

import 'browser_session_host.dart';

final class OhosBrowserSessionException implements BrowserSessionHostException {
  const OhosBrowserSessionException(this.code);

  @override
  final String code;
}

final class OhosBrowserSessionHost implements BrowserSessionHost {
  OhosBrowserSessionHost({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('mgread_plugin_runtime/ohos_browser_session');

  final MethodChannel _channel;
  final Set<String> _jobs = <String>{};
  bool _disposed = false;

  @override
  Future<Map<String, Object?>> request({
    required String jobId,
    required int deadlineUnixMs,
    required Map<String, Object?> raw,
  }) async {
    if (_disposed) throw const OhosBrowserSessionException('unsupported');
    if (jobId.isEmpty ||
        deadlineUnixMs <= DateTime.now().millisecondsSinceEpoch) {
      throw const OhosBrowserSessionException('timeout');
    }
    if (!_jobs.add(jobId))
      throw const OhosBrowserSessionException('overloaded');
    try {
      final value = await _channel.invokeMethod<Object?>(
        'request',
        <String, Object?>{
          'jobId': jobId,
          'deadlineUnixMs': deadlineUnixMs,
          'raw': raw,
        },
      );
      if (value is! Map)
        throw const OhosBrowserSessionException('plugin_execution_failed');
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    } on PlatformException catch (error) {
      throw OhosBrowserSessionException(_stableCode(error.code));
    } on MissingPluginException {
      throw const OhosBrowserSessionException('unsupported');
    } finally {
      _jobs.remove(jobId);
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    if (!_jobs.remove(jobId) || _disposed) return;
    try {
      await _channel.invokeMethod<void>('cancel', <String, Object?>{
        'jobId': jobId,
      });
    } on Object {
      // The Runtime deadline remains authoritative when the host is gone.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _jobs.clear();
    try {
      await _channel.invokeMethod<void>('dispose');
    } on Object {
      // Native disposal is best effort; no Dart-side session survives this.
    }
  }

  String _stableCode(String code) =>
      const <String>{
        'cancelled',
        'interaction_required',
        'overloaded',
        'plugin_execution_failed',
        'timeout',
        'unsupported',
      }.contains(code)
      ? code
      : 'plugin_execution_failed';
}
