import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

import 'package:mg_read/core/content_library/content_library.dart';
import 'package:mg_read/features/discovery/application/source_content_gateway.dart';
import 'package:mg_read/features/reader/data/content_library_source_text_reader.dart';

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
      final dataRoot = await Directory.systemTemp.createTemp('mg-read-ohos-reader-source-');
      final library = await ContentLibrary.open(dataRoot: dataRoot);
      addTearDown(() async {
        await library.close();
        await dataRoot.delete(recursive: true);
      });
      var readerEvidenceRecorded = false;
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
        // ignore: avoid_print
        print('OHOS_REAL_SOURCE_PASS=${source.pluginId}');

        if (!readerEvidenceRecorded && content.contentKind == PluginContentKind.novel) {
          final shelfItem = await library.addLibraryItem(
            BookshelfAddRequest(
              title: detail.summary.title,
              author: detail.summary.author,
              kind: ContentKind.novel,
              pluginId: source.pluginId,
              pluginVersion: source.version,
              remoteContentId: detail.summary.id,
            ),
          );
          final reader = ContentLibrarySourceTextReader(library, _RuntimeSourceGateway(runtime));
          final launch = await reader.launch(shelfItem.id.value);
          final firstChapter = await launch.dataSource.loadChapterAtIndex(launch.bookId, 0);
          final firstContent = await launch.dataSource.loadChapterContent(launch.bookId, firstChapter.id);
          expect(await library.listAllCatalog(shelfItem.id), isNotEmpty);
          expect(firstContent.paragraphs, isNotEmpty);
          expect(firstContent.paragraphs.any((paragraph) => paragraph.text.trim().isNotEmpty), isTrue);
          // ignore: avoid_print
          print('OHOS_READER_SOURCE_PASS=${source.pluginId}');
          readerEvidenceRecorded = true;
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

final class _RuntimeSourceGateway implements SourceContentGateway {
  const _RuntimeSourceGateway(this._runtime);

  final PluginRuntime _runtime;

  @override
  Future<PluginContentDetail> getDetail({required String pluginId, required String id}) =>
      _runtime.invoke(SourceDetailInvocation(pluginId: pluginId, id: id));

  @override
  Future<PluginChaptersResult> getChapters({required String pluginId, required String id}) =>
      _runtime.invoke(SourceChaptersInvocation(pluginId: pluginId, id: id));

  @override
  Future<PluginChapterContent> getContent({required String pluginId, required String id, required String chapterId}) =>
      _runtime.invoke(SourceContentInvocation(pluginId: pluginId, id: id, chapterId: chapterId));

  @override
  Future<List<PluginSourceDescriptor>> listSources() => throw UnsupportedError('Not used by the OHOS reader flow.');

  @override
  Future<PluginDiscoverResult> discover({
    required String pluginId,
    String? target,
    String? cursor,
    String? collectionId,
    int pageSize = 20,
  }) => throw UnsupportedError('Not used by the OHOS reader flow.');

  @override
  Future<PluginSearchResult> search({required String pluginId, required String query, String? cursor, int pageSize = 20}) =>
      throw UnsupportedError('Not used by the OHOS reader flow.');

  @override
  Future<PluginSearchSuggestionsResult> searchSuggestions({required String pluginId, String? cursor, int pageSize = 20}) =>
      throw UnsupportedError('Not used by the OHOS reader flow.');
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
