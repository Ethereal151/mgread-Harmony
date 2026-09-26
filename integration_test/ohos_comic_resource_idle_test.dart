/// Exercises the native OHOS event loop after getContent has returned. All
/// images come from a local fixture; no external source or periodic Runtime
/// ping may keep Node alive while the reader downloads the response bodies.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mg_read/features/reader/data/content_library_source_comic_reader.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

const _pluginId = 'org.mgread.ohos.comic-idle-test';
const _referer = 'https://example.invalid/comic-fixture';
const _pageCount = 4;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS serves comic images while the Runtime bridge is idle', (
    WidgetTester tester,
  ) async {
    if (Platform.operatingSystem != 'ohos') return;
    await tester.runAsync(() async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=',
      );
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final runtime = PluginRuntime();
      final receivedPaths = <String>[];
      final upstreamErrors = <Object>[];
      upstream.listen((request) async {
        try {
          if (request.headers.value(HttpHeaders.refererHeader) != _referer ||
              request.headers.value('x-mgread-fixture') != 'comic-idle') {
            request.response.statusCode = HttpStatus.forbidden;
          } else {
            receivedPaths.add(request.uri.path);
            request.response.headers.contentType = ContentType('image', 'png');
            // Flush headers and split the body to require more than one I/O
            // turn after the manifest invocation has already completed.
            request.response.add(png.sublist(0, 16));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
            request.response.add(png.sublist(16));
          }
          await request.response.close();
        } on Object catch (error) {
          upstreamErrors.add(error);
        }
      });
      addTearDown(() async {
        try {
          await runtime.invoke(
            const UninstallPluginInvocation(pluginId: _pluginId),
          );
        } finally {
          await upstream.close(force: true);
          await runtime.debugDispose();
        }
      });

      final bytes = _fixtureBytes(upstream.port);
      final installed = await runtime.importPluginArtifacts([
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
      ], forceUpgradePluginIds: <String>{_pluginId});
      expect(installed.single.status, PluginTransferImportStatus.installed);

      // Repeat after a core restart: the resource origin changes and the
      // native wakeup handle must remain usable for the same host thread.
      for (var round = 0; round < 2; round++) {
        if (round != 0) {
          await const MethodChannel('mgread_plugin_runtime/ohos')
              .invokeMethod<String>('restart');
        }
        final content = await runtime.invoke(
          const SourceContentInvocation(
            pluginId: _pluginId,
            id: 'comic-fixture',
            chapterId: 'chapter-1',
          ),
        );
        expect(content.contentKind, PluginContentKind.manga);
        expect(content.pages, hasLength(_pageCount));
        for (final page in content.pages) {
          expect(page.url.host, '127.0.0.1');
          expect(page.url.path, startsWith('/v1/source-resource/'));
          expect(page.url.port, isNot(upstream.port));
        }

        // Do not invoke, ping or pump the Runtime bridge during this interval
        // or the image downloads: that would hide the original starvation.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final images = await Future.wait([
          for (final page in content.pages) fetchComicImage(page.url),
        ]).timeout(const Duration(seconds: 10));
        for (final image in images) {
          expect(image, orderedEquals(png));
        }
        expect(upstreamErrors, isEmpty);
        expect(receivedPaths, hasLength((round + 1) * _pageCount));

        // A new control task must also wake the idle libuv poll promptly.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final ping = await runtime
            .invoke(const RuntimePingInvocation())
            .timeout(const Duration(seconds: 5));
        expect(ping.isHealthy, isTrue);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Uint8List _fixtureBytes(int upstreamPort) {
  final code = utf8.encode('''
let context;
export function activate(value) { context = value; }
export function discover() { return { kind: 'document', document: { components: [] } }; }
export function search() { return { items: [], nextCursor: null, totalCount: 0 }; }
export function getDetail() { throw new Error('not used'); }
export function getChapters() { throw new Error('not used'); }
export function getContent(request) {
  return {
    contentKind: 'manga', chapterId: request.chapterId,
    title: null, updatedAt: null, text: null,
    pages: Array.from({ length: $_pageCount }, (_, index) => ({
      id: 'page-' + index, index, width: 1, height: 1, mimeType: 'image/png',
      resourcePolicy: 'sessionOnly', expiresAt: null,
      url: context.resource.proxy({
        kind: 'image', proxyMode: 'direct',
        url: 'http://127.0.0.1:$upstreamPort/page-' + index + '.png',
        headers: { Referer: '$_referer', 'x-mgread-fixture': 'comic-idle' },
      }),
    })),
  };
}
''');
  final descriptor = <String, Object?>{
    'engines': <String, Object?>{'node': '>=24 <25'},
    'main': 'dist/index.mjs',
    'mgread': <String, Object?>{
      'contentKinds': <String>['manga'],
      'displayName': 'OHOS comic idle regression',
      'id': _pluginId,
      'packageMode': 'single-file',
      'pluginApi': 1,
      'schemaVersion': 1,
    },
    'name': '@mgread-test/ohos-comic-idle',
    'type': 'module',
    'version': '0.1.0',
  };
  final envelope = <String, Object?>{
    'codeBytes': code.length,
    'codeSha256': sha256.convert(code).toString(),
    'descriptor': descriptor,
    'formatVersion': 1,
  };
  final payload = base64Url
      .encode(utf8.encode(_canonicalJson(envelope)))
      .replaceAll('=', '');
  final header = utf8.encode('// @mgread-plugin-v1 $payload\n');
  return Uint8List.fromList(<int>[...header, ...code]);
}

String _canonicalJson(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return jsonEncode(value);
  }
  if (value is List<Object?>) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
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
