import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_media/mgread_ohos_media.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

/// OHOS-only Juzi TV acceptance. The host-side runner serves the freshly built
/// single-file artifact over HDC; no source code is copied into the HAP.
const _artifactBaseUrl = String.fromEnvironment('OHOS_JUZI_ARTIFACT_BASE_URL', defaultValue: 'http://127.0.0.1:64524');
const _pluginId = 'org.mgread.juzi-tv';
const _version = '1.1.2';
const _artifactFile = 'org.mgread.juzi-tv-1.1.2.mgplugin.js';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS runs the Juzi TV source and video proxy chain', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final runtime = PluginRuntime();
    await _install(runtime);

    final discovery = await _invokeWithFrames(tester, runtime.invoke(const SourceDiscoverInvocation(pluginId: _pluginId, pageSize: 20)));
    expect(discovery, isA<PluginDiscoveryDocumentResult>());
    final categories = _findCategories((discovery as PluginDiscoveryDocumentResult).document.components);
    expect(categories, isNotNull);
    expect(
      categories!.categories.map((category) => category.target),
      containsAll(<String>['channel:short', 'channel:movie', 'channel:series', 'channel:anime']),
    );

    final suggestions = await _invokeWithFrames(
      tester,
      runtime.invoke(const SourceSearchSuggestionsInvocation(pluginId: _pluginId, pageSize: 10)),
    );
    expect(suggestions.items, isA<List<PluginSearchSuggestion>>());

    for (final id in const <String>['vod:458764', 'vod:35736']) {
      final detail = await _invokeWithFrames(tester, runtime.invoke(SourceDetailInvocation(pluginId: _pluginId, id: id)));
      expect(detail.summary.id, id);
      final cover = detail.summary.coverUrl;
      expect(cover, isNotNull, reason: '$id cover');
      final coverRequest = await runtime.invoke(SourceResourceDecodeInvocation(url: cover.toString()));
      expect(coverRequest.pluginId, _pluginId);
      await _probeHttpResource(coverRequest.request, label: '$id cover');

      final search = await _invokeWithFrames(
        tester,
        runtime.invoke(SourceSearchInvocation(pluginId: _pluginId, query: detail.summary.title, pageSize: 10)),
      );
      expect(search.items.any((item) => item.id == id), isTrue, reason: '$id search');

      final chapters = await _invokeWithFrames(tester, runtime.invoke(SourceChaptersInvocation(pluginId: _pluginId, id: id)));
      expect(chapters.items, isNotEmpty, reason: '$id chapters');
      for (final group in chapters.groups) {
        expect(group.episodes.map((episode) => episode.order), orderedEquals(List<int>.generate(group.episodes.length, (index) => index)));
        expect(group.episodes.length, lessThanOrEqualTo(2000), reason: '$id line limit');
      }

      final firstChapter = chapters.items.first;
      final content = await _invokeWithFrames(
        tester,
        runtime.invoke(SourceContentInvocation(pluginId: _pluginId, id: id, chapterId: firstChapter.id)),
      );
      expect(content.chapterId, firstChapter.id);
      expect(content.contentKind, PluginContentKind.video);
      final media = content.media;
      expect(media, isNotNull, reason: '$id media');
      final mediaRequest = await runtime.invoke(SourceResourceDecodeInvocation(url: media!.url.toString()));
      expect(mediaRequest.pluginId, _pluginId);
      await _probeHttpResource(mediaRequest.request, label: '$id media', mediaType: media.resourceType);

      if (id == 'vod:458764') {
        await _playVideo(tester, mediaRequest.request, media.resourceType);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<void> _install(PluginRuntime runtime) async {
  final installed = await runtime.invoke(const InstalledPluginsInvocation());
  final current = installed.where((plugin) => plugin.id == _pluginId);
  if (current.isNotEmpty && current.single.activeVersion == _version && current.single.status == 'active') return;

  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse('$_artifactBaseUrl/$_artifactFile'))).close();
    expect(response.statusCode, HttpStatus.ok, reason: _artifactFile);
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
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
            version: _version,
          ),
          bytes: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
        ),
      ],
      forceUpgradePluginIds: const <String>{_pluginId},
    );
    expect(result.single.status, PluginTransferImportStatus.installed);
  } finally {
    client.close(force: true);
  }
}

PluginDiscoveryCategoryCollectionComponent? _findCategories(Iterable<PluginDiscoveryComponent> components) {
  for (final component in components) {
    if (component is PluginDiscoveryCategoryCollectionComponent) return component;
    if (component case PluginDiscoverySectionComponent(:final children) || PluginDiscoveryGroupComponent(:final children)) {
      final nested = _findCategories(children);
      if (nested != null) return nested;
    }
  }
  return null;
}

Future<void> _probeHttpResource(Map<String, Object?> request, {required String label, PluginMediaResourceType? mediaType}) async {
  final url = request['url'];
  final rawHeaders = request['headers'];
  expect(url, isA<String>(), reason: label);
  final headers = <String, String>{
    if (rawHeaders is Map<Object?, Object?>)
      for (final entry in rawHeaders.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
  };
  final client = HttpClient();
  try {
    final httpRequest = await client.getUrl(Uri.parse(url as String));
    for (final entry in headers.entries) {
      httpRequest.headers.set(entry.key, entry.value);
    }
    if (mediaType == PluginMediaResourceType.video) httpRequest.headers.set('Range', 'bytes=0-65535');
    final response = await httpRequest.close().timeout(const Duration(seconds: 30));
    expect(response.statusCode, inInclusiveRange(200, 299), reason: '$label status ${response.statusCode}');
    if (mediaType == PluginMediaResourceType.hls) {
      expect(await response.transform(utf8.decoder).join(), startsWith('#EXTM3U'), reason: label);
    } else {
      expect((await response.take(1).toList()).isNotEmpty, isTrue, reason: label);
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _playVideo(WidgetTester tester, Map<String, Object?> request, PluginMediaResourceType type) async {
  final url = request['url'];
  expect(url, isA<String>());
  final rawHeaders = request['headers'];
  final headers = <String, String>{
    if (rawHeaders is Map<Object?, Object?>)
      for (final entry in rawHeaders.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
  };
  final sessionId = 'ohos-juzi-tv-458764';
  final firstFrame = Completer<void>();
  final position = Completer<void>();
  final events = <OhosMediaEvent>[];
  final subscription = OhosMediaClient.instance.events.where((event) => event.sessionId == sessionId).listen((event) {
    events.add(event);
    if (event.kind == 'firstFrame' && !firstFrame.isCompleted) {
      firstFrame.complete();
    }
    if (event.kind == 'position' && (event.value as num?)?.toDouble() != null && (event.value! as num) > 0 && !position.isCompleted) {
      position.complete();
    }
  });
  addTearDown(subscription.cancel);
  addTearDown(() => OhosMediaClient.instance.command('dispose', sessionId));
  final opened = await OhosMediaClient.instance.openVideo(
    sessionId: sessionId,
    uri: Uri.parse(url as String),
    headers: headers,
    resourceType: type == PluginMediaResourceType.hls ? 'hls' : 'video',
    initialPosition: Duration.zero,
    play: false,
  );
  expect(opened.textureId, isNotNull);
  await tester.pumpWidget(Texture(textureId: opened.textureId!));
  await OhosMediaClient.instance.command('play', sessionId);
  await firstFrame.future.timeout(const Duration(seconds: 45));
  await position.future.timeout(const Duration(seconds: 45));
  expect(events.any((event) => event.kind == 'playing' || event.kind == 'state' && event.value == 'playing'), isTrue);
  await OhosMediaClient.instance.command('dispose', sessionId);
}

Future<T> _invokeWithFrames<T>(WidgetTester tester, Future<T> invocation) async {
  var completed = false;
  T? value;
  Object? failure;
  StackTrace? stack;
  invocation.then<void>(
    (result) {
      value = result;
      completed = true;
    },
    onError: (Object error, StackTrace trace) {
      failure = error;
      stack = trace;
      completed = true;
    },
  );
  while (!completed) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
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
