import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/features/network_proxy/application/flutter_network_proxy_manager.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

const _pluginId = 'org.mgread.ohos.https-proxy-smoke';
const _useSystemProxy = bool.fromEnvironment('OHOS_RUNTIME_SYSTEM_PROXY_MODE');
const _systemProxyPort = int.fromEnvironment('OHOS_RUNTIME_SYSTEM_PROXY_PORT', defaultValue: 35555);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS arm64 Runtime reaches HTTPS through an explicit CONNECT proxy', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final proxy = await _ConnectProxy.start(port: _useSystemProxy ? _systemProxyPort : null);
    final runtime = PluginRuntime();
    addTearDown(() async {
      await runtime.configurePluginHttpProxy(null);
      await runtime.invoke(const UninstallPluginInvocation(pluginId: _pluginId));
      await proxy.close();
    });

    final bytes = _proxyFixtureBytes();
    final result = await runtime.importPluginArtifacts(
      <({PluginTransferArtifact artifact, Stream<List<int>> bytes})>[
        (
          artifact: PluginTransferArtifact(
            bytes: bytes.length,
            developmentFingerprint: null,
            developmentRevision: null,
            format: PluginArtifactFormat.singleFile,
            pluginId: _pluginId,
            provenance: PluginArtifactProvenance.installed,
            checksum: _crc32(bytes),
            version: '0.1.0',
          ),
          bytes: Stream<List<int>>.value(bytes),
        ),
      ],
      forceUpgradePluginIds: <String>{_pluginId},
    );
    expect(result.single.status, PluginTransferImportStatus.installed);

    final proxyUri = _useSystemProxy ? await _readConfiguredSystemProxy() : Uri(scheme: 'http', host: '127.0.0.1', port: proxy.port);
    expect(proxyUri, isNotNull);
    await runtime.configurePluginHttpProxy(proxyUri!);
    final search = await runtime.invoke(const SourceSearchInvocation(pluginId: _pluginId, query: 'https-connect'));

    expect(search.items, hasLength(1));
    expect(search.items.single.title, 'https:200:true');
    expect(proxy.connectCount, greaterThan(0));
    expect(proxy.targetHosts, contains('example.com'));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<Uri?> _readConfiguredSystemProxy() async {
  final manager = FlutterNetworkProxyManager(operatingSystem: 'ohos', ohosProxyConfigurator: (_) async {});
  final proxy = await manager.runtimeSourceProxyUri();
  expect(proxy?.host, '127.0.0.1');
  expect(proxy?.port, _systemProxyPort);
  return proxy;
}

Uint8List _proxyFixtureBytes() {
  final code = utf8.encode(r'''let context;
export async function activate(nextContext) { context = nextContext; }
export async function search() {
  const response = await context.http.fetch('https://example.com/', { headers: { accept: 'text/html' } });
  const body = await response.text();
  return {
    pluginId: 'org.mgread.ohos.https-proxy-smoke',
    sourceName: 'OHOS HTTPS proxy smoke',
    items: [{
        id: 'https-connect-book',
        title: `https:${response.status}:${body.includes('Example Domain')}`,
        contentKind: 'novel',
        author: null,
        url: 'https://example.com/',
        coverUrl: null,
        description: null,
        language: 'en',
        status: 'completed',
        access: 'free',
        wordCount: null,
        chapterCount: null,
        publishedAt: null,
        updatedAt: null,
        latestChapter: null,
        categories: [],
        tags: [],
        attributes: [],
    }],
    nextCursor: null,
    totalCount: 1,
  };
}
export async function discover() { return { kind: 'document', document: { components: [] } }; }
export async function getDetail() { throw new Error('not used'); }
export async function getChapters() { throw new Error('not used'); }
export async function getContent() { throw new Error('not used'); }
''');
  final descriptor = <String, Object?>{
    'engines': <String, Object?>{'node': '>=24 <25'},
    'main': 'dist/index.mjs',
    'mgread': <String, Object?>{
      'contentKinds': <String>['novel'],
      'displayName': 'OHOS HTTPS proxy smoke',
      'id': _pluginId,
      'packageMode': 'single-file',
      'pluginApi': 1,
      'schemaVersion': 1,
    },
    'name': '@mgread-test/ohos-https-proxy-smoke',
    'type': 'module',
    'version': '0.1.0',
  };
  final envelope = <String, Object?>{
    'codeBytes': code.length,
    'codeSha256': sha256.convert(code).toString(),
    'descriptor': descriptor,
    'formatVersion': 1,
  };
  final header = utf8.encode('// @mgread-plugin-v1 ${base64Url.encode(utf8.encode(_canonicalJson(envelope))).replaceAll('=', '')}\n');
  return Uint8List.fromList(<int>[...header, ...code]);
}

String _canonicalJson(Object? value) {
  if (value == null || value is bool || value is num || value is String) return jsonEncode(value);
  if (value is List<Object?>) return '[${value.map(_canonicalJson).join(',')}]';
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  throw StateError('Unsupported canonical JSON value: ${value.runtimeType}');
}

String _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

final class _ConnectProxy {
  _ConnectProxy._(this._server);

  final ServerSocket _server;
  final Set<String> targetHosts = <String>{};
  int connectCount = 0;

  int get port => _server.port;

  static Future<_ConnectProxy> start({int? port}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port ?? 0);
    final proxy = _ConnectProxy._(server);
    server.listen(proxy._accept);
    return proxy;
  }

  Future<void> close() => _server.close();

  void _accept(Socket client) {
    final state = _ProxyConnection(client);
    unawaited(state.run(onConnect: () => connectCount++, onTarget: targetHosts.add));
  }
}

final class _ProxyConnection {
  _ProxyConnection(this.client);

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
      final isConnect = method.toUpperCase() == 'CONNECT';
      final uri = isConnect ? Uri.parse('http://$target') : Uri.parse(target);
      final host = uri.host;
      final port = uri.hasPort ? uri.port : (isConnect ? 443 : 80);
      if (host.isEmpty) throw const FormatException('Missing proxy target.');
      final upstream = await Socket.connect(host, port, timeout: const Duration(seconds: 20));
      _upstream = upstream;
      onTarget(host);
      if (isConnect) {
        onConnect();
        client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
        upstream.add(remainder);
      } else {
        final path = uri.path.isEmpty ? '/' : uri.path + (uri.hasQuery ? '?${uri.query}' : '');
        final rewritten = <String>['$method $path HTTP/1.1'];
        for (final line in lines.skip(1)) {
          if (line.isEmpty || line.toLowerCase().startsWith('proxy-connection:')) continue;
          rewritten.add(line);
        }
        rewritten.add('');
        rewritten.add('');
        upstream.add(utf8.encode(rewritten.join('\r\n')));
        upstream.add(remainder);
      }
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
