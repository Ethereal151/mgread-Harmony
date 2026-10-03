import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

const _artifactBaseUrl = String.fromEnvironment(
  'OHOS_BAOZIMH_ARTIFACT_BASE_URL',
  defaultValue: 'http://127.0.0.1:64524',
);
const _pluginId = 'org.mgread.baozimh-com';
const _version = '1.0.6';
const _artifactFile = 'org.mgread.baozimh-com-1.0.6.mgplugin.js';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS real Baozimh source discovery to comic resources', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    await tester.pumpWidget(const MaterialApp(home: OhosBrowserSessionSurface(prewarm: true)));
    await tester.pump();

    final runtime = PluginRuntime();
    debugPrint('BAOZIMH_ARTIFACT_BASE_URL=$_artifactBaseUrl');
    final artifact = await _downloadArtifact();
    addTearDown(() async {
      await runtime.invoke(const UninstallPluginInvocation(pluginId: _pluginId));
    });
    await runtime.importPluginArtifacts(
      <({PluginTransferArtifact artifact, Stream<List<int>> bytes})>[
        (
          artifact: PluginTransferArtifact(
            bytes: artifact.length,
            developmentFingerprint: null,
            developmentRevision: null,
            format: PluginArtifactFormat.singleFile,
            pluginId: _pluginId,
            provenance: PluginArtifactProvenance.installed,
            checksum: _crc32(artifact),
            version: _version,
          ),
          bytes: Stream<List<int>>.value(artifact),
        ),
      ],
      forceUpgradePluginIds: <String>{_pluginId},
    );

    debugPrint('BAOZIMH_FLOW=discover:start');
    late final PluginDiscoverResult discovery;
    discovery = await _invokeWithFrames(
      tester,
      runtime.invoke<PluginDiscoverResult>(const SourceDiscoverInvocation(pluginId: _pluginId, pageSize: 20)),
    );
    debugPrint('BAOZIMH_FLOW=discover:done');
    expect(discovery, isA<PluginDiscoveryDocumentResult>());
    final summary = _firstContent(discovery as PluginDiscoveryDocumentResult);
    expect(summary, isNotNull);

    debugPrint('BAOZIMH_FLOW=detail:start id=${summary!.id}');
    final detail = await _invokeWithFrames(
      tester,
      runtime.invoke(SourceDetailInvocation(pluginId: _pluginId, id: summary!.id)),
    );
    debugPrint('BAOZIMH_FLOW=detail:done');
    debugPrint('BAOZIMH_FLOW=chapters:start');
    final chapters = await _invokeWithFrames(
      tester,
      runtime.invoke(SourceChaptersInvocation(pluginId: _pluginId, id: detail.summary.id)),
    );
    debugPrint('BAOZIMH_FLOW=chapters:done count=${chapters.items.length}');
    expect(chapters.items, isNotEmpty);

    debugPrint('BAOZIMH_FLOW=content:first:start');
    final first = await _invokeWithFrames(
      tester,
      runtime.invoke(SourceContentInvocation(
        pluginId: _pluginId,
        id: detail.summary.id,
        chapterId: chapters.items.first.id,
      )),
    );
    debugPrint('BAOZIMH_FLOW=content:first:done pages=${first.pages.length}');
    expect(first.contentKind, PluginContentKind.manga);
    expect(first.pages, isNotEmpty);
    final firstBytes = await _fetch(first.pages.first.url);
    expect(firstBytes, isNotEmpty);

    if (chapters.items.length > 1) {
      debugPrint('BAOZIMH_FLOW=content:second:start');
      final second = await _invokeWithFrames(
        tester,
        runtime.invoke(SourceContentInvocation(
          pluginId: _pluginId,
          id: detail.summary.id,
          chapterId: chapters.items[1].id,
        )),
      );
      debugPrint('BAOZIMH_FLOW=content:second:done pages=${second.pages.length}');
      expect(second.contentKind, PluginContentKind.manga);
      expect(second.pages, isNotEmpty);
      expect(await _fetch(second.pages.first.url), isNotEmpty);
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<List<int>> _downloadArtifact() async {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  try {
    final uri = Uri.parse('$_artifactBaseUrl/$_artifactFile');
    debugPrint('BAOZIMH_DOWNLOAD_URI=$uri');
    final request = await client.getUrl(uri);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    return await response.fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _fetch(Uri uri) async {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 45));
    expect(response.statusCode, HttpStatus.ok, reason: uri.toString());
    return await response.fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
  } finally {
    client.close(force: true);
  }
}

PluginContentSummary? _firstContent(PluginDiscoveryDocumentResult result) {
  PluginContentSummary? found;
  void visit(PluginDiscoveryComponent component) {
    if (found != null) return;
    if (component case PluginDiscoveryContentCollectionComponent(:final items)) {
      if (items.isNotEmpty) found = items.first.content;
      return;
    }
    if (component case PluginDiscoverySectionComponent(:final children)) {
      for (final child in children) visit(child);
    } else if (component case PluginDiscoveryGroupComponent(:final children)) {
      for (final child in children) visit(child);
    }
  }
  for (final component in result.document.components) visit(component);
  return found;
}

Future<T> _invokeWithFrames<T>(WidgetTester tester, Future<T> invocation) async {
  var completed = false;
  T? value;
  Object? error;
  StackTrace? stack;
  invocation.then<void>((result) {
    value = result;
    completed = true;
  }, onError: (Object caught, StackTrace caughtStack) {
    error = caught;
    stack = caughtStack;
    completed = true;
  });
  while (!completed) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
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
