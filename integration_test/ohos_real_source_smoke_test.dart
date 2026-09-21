import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

/// Real arm64 OHOS source-chain evidence. The host-side runner serves the
/// built artifacts through an HDC TCP forward; no source code or network
/// response is embedded in the HAP.
const String _artifactBaseUrl = String.fromEnvironment(
  'OHOS_REAL_SOURCE_ARTIFACT_BASE_URL',
  defaultValue: 'http://127.0.0.1:64524',
);

const List<_SourceSpec> _sources = <_SourceSpec>[
  _SourceSpec(
    pluginId: 'org.mgread.35ge-info',
    version: '1.0.2',
    query: '斗破苍穹',
    artifactFile: 'org.mgread.35ge-info-1.0.2.mgplugin.js',
  ),
  _SourceSpec(
    pluginId: 'org.mgread.deqi-novel',
    version: '1.0.0',
    query: '斗破苍穹',
    artifactFile: 'org.mgread.deqi-novel-1.0.0.mgplugin.js',
  ),
  _SourceSpec(
    pluginId: 'org.mgread.fanqie-novel',
    version: '1.0.0',
    query: '旧版书',
    artifactFile: 'org.mgread.fanqie-novel-1.0.0.mgplugin.js',
  ),
  _SourceSpec(
    pluginId: 'org.mgread.midu-novel',
    version: '1.0.0',
    query: '斗破苍穹',
    artifactFile: 'org.mgread.midu-novel-1.0.0.mgplugin.js',
  ),
  _SourceSpec(
    pluginId: 'org.mgread.shukuge-365',
    version: '1.0.2',
    query: '斗破苍穹',
    artifactFile: 'org.mgread.shukuge-365-1.0.2.mgplugin.js',
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'OHOS arm64 runs five real source discovery-to-content chains',
    (WidgetTester tester) async {
      if (Platform.operatingSystem != 'ohos') return;

      final runtime = PluginRuntime();
      final installed = await runtime.invoke(const InstalledPluginsInvocation());
      for (final source in _sources) {
        final current = installed.where((plugin) => plugin.id == source.pluginId);
        if (current.isNotEmpty && current.single.activeVersion == source.version && current.single.status == 'active') {
          continue;
        }
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse('$_artifactBaseUrl/${source.artifactFile}'));
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok, reason: source.artifactFile);
        final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
        client.close(force: true);
        final result = await runtime.importPluginArtifacts(<({PluginTransferArtifact artifact, Stream<List<int>> bytes})>[
          (
            artifact: PluginTransferArtifact(
              bytes: bytes.length,
              developmentFingerprint: null,
              developmentRevision: null,
              format: PluginArtifactFormat.singleFile,
              pluginId: source.pluginId,
              provenance: PluginArtifactProvenance.installed,
              checksum: _crc32(bytes),
              version: source.version,
            ),
            bytes: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
          ),
        ], forceUpgradePluginIds: <String>{source.pluginId});
        expect(result.single.status, PluginTransferImportStatus.installed, reason: source.pluginId);
      }

      for (final source in _sources) {
        final discovery = await _invokeWithFrames(
          tester,
          runtime.invoke(SourceDiscoverInvocation(pluginId: source.pluginId, pageSize: 5)),
        );
        expect(discovery, isA<PluginDiscoveryDocumentResult>(), reason: source.pluginId);

        final search = await _invokeWithFrames(
          tester,
          runtime.invoke(SourceSearchInvocation(pluginId: source.pluginId, query: source.query, pageSize: 5)),
        );
        expect(search.items, isNotEmpty, reason: source.pluginId);

        final detail = await _invokeWithFrames(
          tester,
          runtime.invoke(SourceDetailInvocation(pluginId: source.pluginId, id: search.items.first.id)),
        );
        final chapters = await _invokeWithFrames(
          tester,
          runtime.invoke(SourceChaptersInvocation(pluginId: source.pluginId, id: detail.summary.id)),
        );
        expect(chapters.items, isNotEmpty, reason: source.pluginId);

        final content = await _invokeWithFrames(
          tester,
          runtime.invoke(
            SourceContentInvocation(
              pluginId: source.pluginId,
              id: detail.summary.id,
              chapterId: chapters.items.first.id,
            ),
          ),
        );
        expect(content.text?.trim(), isNotEmpty, reason: source.pluginId);
        print('OHOS_REAL_SOURCE_PASS=${source.pluginId}');
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<T> _invokeWithFrames<T>(WidgetTester tester, Future<T> invocation) async {
  var completed = false;
  T? value;
  Object? failure;
  StackTrace? failureStack;
  invocation.then<void>(
    (result) {
      value = result;
      completed = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      failure = error;
      failureStack = stackTrace;
      completed = true;
    },
  );
  while (!completed) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (failure case final error?) {
    Error.throwWithStackTrace(error, failureStack!);
  }
  return value as T;
}

final class _SourceSpec {
  const _SourceSpec({required this.pluginId, required this.version, required this.query, required this.artifactFile});

  final String pluginId;
  final String version;
  final String query;
  final String artifactFile;
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
