import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Small CONNECT tunnel used by OHOS integration tests that exercise ArkWeb.
final class OhosConnectProxy {
  OhosConnectProxy._(this._server);

  final ServerSocket _server;
  final Set<String> targetHosts = <String>{};
  int connectCount = 0;

  int get port => _server.port;

  static Future<OhosConnectProxy> start({int? port}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port ?? 0);
    final proxy = OhosConnectProxy._(server);
    server.listen(proxy._accept);
    return proxy;
  }

  Future<void> close() => _server.close();

  void _accept(Socket client) {
    final connection = _ConnectConnection(client);
    unawaited(connection.run(onConnect: () => connectCount++, onTarget: targetHosts.add));
  }
}

final class _ConnectConnection {
  _ConnectConnection(this.client);

  final Socket client;
  final BytesBuilder _header = BytesBuilder(copy: false);
  final List<List<int>> _pending = <List<int>>[];
  StreamSubscription<List<int>>? _subscription;
  Socket? _upstream;
  bool _prepared = false;
  bool _closed = false;

  Future<void> run({required VoidCallback onConnect, required ValueChanged<String> onTarget}) async {
    _subscription = client.listen(
      (chunk) {
        if (_prepared) {
          if (_upstream case final upstream?) {
            upstream.add(chunk);
          } else {
            _pending.add(chunk);
          }
          return;
        }
        _header.add(chunk);
        final bytes = _header.toBytes();
        final end = _headerEnd(bytes);
        if (end < 0) return;
        _prepared = true;
        final initial = bytes.sublist(0, end);
        final remainder = bytes.sublist(end);
        unawaited(_prepare(initial, remainder, onConnect: onConnect, onTarget: onTarget));
      },
      onError: (_) => _finish(),
      onDone: _finish,
      cancelOnError: true,
    );
    await _subscription!.asFuture<void>();
  }

  Future<void> _prepare(
    List<int> headerBytes,
    List<int> remainder, {
    required VoidCallback onConnect,
    required ValueChanged<String> onTarget,
  }) async {
    try {
      final header = ascii.decode(headerBytes, allowInvalid: true);
      final lines = header.split('\r\n');
      final requestLine = lines.first.split(' ');
      if (requestLine.length < 2) throw const FormatException('Invalid proxy request line.');
      final method = requestLine[0];
      final target = requestLine[1];
      if (method.toUpperCase() != 'CONNECT') throw const FormatException('Only CONNECT requests are supported.');
      final uri = Uri.parse('http://$target');
      final host = uri.host;
      final port = uri.hasPort ? uri.port : 443;
      if (host.isEmpty) throw const FormatException('Missing proxy target.');
      final upstream = await Socket.connect(host, port, timeout: const Duration(seconds: 20));
      _upstream = upstream;
      onTarget(host);
      onConnect();
      client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      upstream.add(remainder);
      for (final chunk in _pending) {
        upstream.add(chunk);
      }
      _pending.clear();
      unawaited(upstream.listen(client.add, onError: (_) => _finish(), onDone: _finish).asFuture<void>());
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    unawaited(_upstream?.close() ?? Future<void>.value());
    unawaited(client.close());
  }
}

int _headerEnd(List<int> bytes) {
  for (var index = 3; index < bytes.length; index++) {
    if (bytes[index - 3] == 13 && bytes[index - 2] == 10 && bytes[index - 1] == 13 && bytes[index] == 10) return index + 1;
  }
  return -1;
}
