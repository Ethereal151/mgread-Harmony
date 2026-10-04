import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/features/network_proxy/application/flutter_network_proxy_manager.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';
import 'fixtures/ohos_connect_proxy.dart';

const _pluginId = 'org.mgread.ohos.https-proxy-smoke';
const _useSystemProxy = bool.fromEnvironment('OHOS_RUNTIME_SYSTEM_PROXY_MODE');
const _systemProxyHost = String.fromEnvironment('OHOS_RUNTIME_SYSTEM_PROXY_HOST', defaultValue: '127.0.0.1');
const _systemProxyPort = int.fromEnvironment('OHOS_RUNTIME_SYSTEM_PROXY_PORT', defaultValue: 35555);
const _expectedSystemProxyNoProxy = String.fromEnvironment('OHOS_RUNTIME_EXPECT_NO_PROXY');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Runtime reaches HTTPS through an explicit CONNECT proxy', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final proxy = await OhosConnectProxy.start(port: _useSystemProxy ? _systemProxyPort : null);
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

    ({Uri? proxyUri, String? noProxy})? systemProxy;
    if (_useSystemProxy) {
      final manager = FlutterNetworkProxyManager(operatingSystem: 'ohos', ohosProxyConfigurator: (_) async {});
      final configuration = await manager.runtimeSourceProxyConfiguration();
      systemProxy = configuration;
      expect(configuration.proxyUri?.host, _systemProxyHost);
      expect(configuration.proxyUri?.port, _systemProxyPort);
      if (_expectedSystemProxyNoProxy.isNotEmpty) {
        expect(configuration.noProxy, contains(_expectedSystemProxyNoProxy));
      }
    }
    final proxyUri = systemProxy?.proxyUri ?? Uri(scheme: 'http', host: '127.0.0.1', port: proxy.port);
    expect(proxyUri, isNotNull);
    await runtime.configurePluginHttpProxy(proxyUri, noProxy: systemProxy?.noProxy);
    final search = await runtime.invoke(const SourceSearchInvocation(pluginId: _pluginId, query: 'https-connect'));

    expect(search.items, hasLength(1));
    expect(search.items.single.title, 'https:200:true');
    if (!_useSystemProxy) {
      expect(proxy.connectCount, greaterThan(0));
      expect(proxy.targetHosts, contains('example.com'));
    }
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 5)));
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
