import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

const String _artifactsJson = String.fromEnvironment('MGREAD_STAGE2_ARTIFACTS_JSON');

const List<String> _fixtureIds = <String>[
  'org.mgread.ohos.stage2.source-one',
  'org.mgread.ohos.stage2.source-two',
  'org.mgread.ohos.stage2.cookie-js',
  'org.mgread.ohos.stage2.javascript',
  'org.mgread.ohos.stage2.interaction',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS Stage 2 covers five sources, Cookie/JS and interaction_required recovery', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    await tester.pumpWidget(const MaterialApp(home: OhosBrowserSessionSurface(prewarm: true)));
    await tester.pump();

    final runtime = PluginRuntime();
    final artifacts = _decodeArtifacts();
    final installed = await runtime.invoke(const InstalledPluginsInvocation());
    debugPrint(
      'STAGE2_INSTALLED=${jsonEncode(installed.map((plugin) => <String, Object?>{'id': plugin.id, 'activeVersion': plugin.activeVersion, 'pendingVersion': plugin.pendingVersion, 'status': plugin.status}).toList())}',
    );
    debugPrint('STAGE2_TRANSFER=${jsonEncode(_fixtureIds.map((id) => artifacts[id]!.artifact.toJson()).toList())}');
    final missing = <({PluginTransferArtifact artifact, Stream<List<int>> bytes})>[];
    for (final id in _fixtureIds) {
      final fixture = artifacts[id];
      expect(fixture, isNotNull, reason: 'Missing host-built fixture artifact for $id.');
      final matching = installed.where((plugin) => plugin.id == id);
      final current = matching.isEmpty ? null : matching.first;
      if (current?.status == 'active' && current?.activeVersion == fixture!.version) continue;
      missing.add((artifact: fixture!.artifact, bytes: Stream<List<int>>.fromIterable(<List<int>>[fixture.bytes])));
    }
    if (missing.isNotEmpty) {
      for (final item in missing) {
        final plan = await runtime.invoke(
          PluginTransferPlanInvocation(
            artifacts: <PluginTransferArtifact>[item.artifact],
            forceUpgradePluginIds: <String>{item.artifact.pluginId},
          ),
        );
        debugPrint(
          'STAGE2_PLAN=${jsonEncode(plan.map((entry) => <String, Object?>{'id': entry.pluginId, 'action': entry.action.name, 'receiverVersion': entry.receiverVersion, 'version': entry.version}).toList())}',
        );
        // A previous interrupted device run may have left the same version in
        // the Runtime's pending tree. This is an explicit test fixture
        // replacement, so use the same force-upgrade path as the product's
        // confirmed plugin replacement flow instead of treating a retry as a
        // downgrade/equal-version request.
        final imports = await runtime.importPluginArtifacts(
          <({PluginTransferArtifact artifact, Stream<List<int>> bytes})>[item],
          forceUpgradePluginIds: <String>{item.artifact.pluginId},
        );
        expect(imports, hasLength(1));
        expect(imports.single.status, PluginTransferImportStatus.installed);
      }
    }

    for (final id in _fixtureIds) {
      final discovery = await runtime.invoke(SourceDiscoverInvocation(pluginId: id, pageSize: 20));
      expect(discovery, isA<PluginDiscoveryDocumentResult>(), reason: id);
      final search = await _invokeWithFrames(tester, runtime.invoke(SourceSearchInvocation(pluginId: id, query: 'stage2', pageSize: 20)));
      expect(search.items, hasLength(1), reason: id);
      final detail = await runtime.invoke(SourceDetailInvocation(pluginId: id, id: search.items.single.id));
      expect(detail.summary.coverUrl, isNotNull, reason: '$id resource proxy');
      final chapters = await runtime.invoke(SourceChaptersInvocation(pluginId: id, id: detail.summary.id));
      expect(chapters.items, hasLength(2), reason: id);
      final content = await runtime.invoke(
        SourceContentInvocation(pluginId: id, id: detail.summary.id, chapterId: chapters.items.first.id),
      );
      expect(content.text, contains('Runtime'), reason: id);
    }

    final cookieTitle = (await _invokeWithFrames(
      tester,
      runtime.invoke(const SourceSearchInvocation(pluginId: 'org.mgread.ohos.stage2.cookie-js', query: 'stage2')),
    )).items.single.title;
    expect(cookieTitle, 'cookie-js:200:true:true');

    final jsTitle = (await _invokeWithFrames(
      tester,
      runtime.invoke(const SourceSearchInvocation(pluginId: 'org.mgread.ohos.stage2.javascript', query: 'stage2')),
    )).items.single.title;
    expect(jsTitle, startsWith('js:'));
    expect(jsTitle, contains(':true:true'));

    PluginRuntimeException? interactionFailure;
    try {
      await _invokeWithFrames(
        tester,
        runtime.invoke(const SourceSearchInvocation(pluginId: 'org.mgread.ohos.stage2.interaction', query: 'interaction-required')),
      );
    } on PluginRuntimeException catch (error) {
      interactionFailure = error;
    }
    expect(interactionFailure?.code, 'interaction_required');
    final interactionTitle = (await _invokeWithFrames(
      tester,
      runtime.invoke(const SourceSearchInvocation(pluginId: 'org.mgread.ohos.stage2.interaction', query: 'stage2')),
    )).items.single.title;
    expect(interactionTitle, 'interaction_required:true');

    final cancellation = PluginInvocationCancellation();
    final delayedInvocation = runtime.invoke(
      const SourceSearchInvocation(pluginId: 'org.mgread.ohos.stage2.source-one', query: 'cancel'),
      cancellation: cancellation,
    );
    await tester.pump(const Duration(milliseconds: 300));
    cancellation.cancel();
    PluginRuntimeException? cancellationFailure;
    try {
      await _invokeWithFrames(tester, delayedInvocation);
    } on PluginRuntimeException catch (error) {
      cancellationFailure = error;
    }
    expect(cancellationFailure?.code, 'cancelled');
    final postCancellation = await runtime.invoke(
      const SourceSearchInvocation(pluginId: 'org.mgread.ohos.stage2.source-one', query: 'stage2'),
    );
    expect(postCancellation.items, hasLength(1));

    // Keep the device fixture set bounded and prove the destructive Runtime
    // lifecycle boundary on the same arm64 host. The next run reinstalls the
    // fixture through the normal import path when it is absent.
    await runtime.invoke(const UninstallPluginInvocation(pluginId: 'org.mgread.ohos.stage2.source-one'));
    final afterUninstall = await runtime.invoke(const InstalledPluginsInvocation());
    expect(afterUninstall.any((plugin) => plugin.id == 'org.mgread.ohos.stage2.source-one'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 8)));
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

Map<String, _FixtureArtifact> _decodeArtifacts() {
  if (_artifactsJson.isEmpty) return _embeddedFixtureArtifacts();
  final raw = jsonDecode(_artifactsJson);
  expect(raw, isA<Map<Object?, Object?>>());
  final result = <String, _FixtureArtifact>{};
  for (final entry in (raw as Map<Object?, Object?>).entries) {
    final id = entry.key as String;
    final bytes = base64Url.decode(entry.value as String);
    final newline = bytes.indexOf(10);
    expect(newline, greaterThan(0), reason: id);
    const prefix = '// @mgread-plugin-v1 ';
    final header = utf8.decode(bytes.sublist(0, newline));
    expect(header, startsWith(prefix), reason: id);
    final envelope = jsonDecode(utf8.decode(base64Url.decode(header.substring(prefix.length)))) as Map<Object?, Object?>;
    final descriptor = envelope['descriptor'] as Map<Object?, Object?>;
    final pluginId = (descriptor['mgread'] as Map<Object?, Object?>)['id'] as String;
    expect(pluginId, id);
    final version = descriptor['version'] as String;
    result[id] = _FixtureArtifact(
      artifact: PluginTransferArtifact(
        bytes: bytes.length,
        developmentFingerprint: null,
        developmentRevision: null,
        format: PluginArtifactFormat.singleFile,
        pluginId: id,
        provenance: PluginArtifactProvenance.installed,
        checksum: _crc32(bytes),
        version: version,
      ),
      bytes: bytes,
      version: version,
    );
  }
  return result;
}

Map<String, _FixtureArtifact> _embeddedFixtureArtifacts() {
  return <String, _FixtureArtifact>{for (final id in _fixtureIds) id: _buildEmbeddedArtifact(id)};
}

_FixtureArtifact _buildEmbeddedArtifact(String id) {
  final codeBytes = utf8.encode(_embeddedFixtureCode);
  final descriptor = <String, Object?>{
    'engines': <String, Object?>{'node': '>=24 <25'},
    'main': 'dist/index.mjs',
    'mgread': <String, Object?>{
      'contentKinds': <String>['novel'],
      'displayName': 'OHOS Stage 2 $id',
      'id': id,
      'packageMode': 'single-file',
      'pluginApi': 1,
      'schemaVersion': 1,
    },
    'name': '@mgread-test/${id.substring('org.mgread.ohos.stage2.'.length)}',
    'type': 'module',
    'version': '0.1.2',
  };
  final envelope = <String, Object?>{
    'codeBytes': codeBytes.length,
    'codeSha256': sha256.convert(codeBytes).toString(),
    'descriptor': descriptor,
    'formatVersion': 1,
  };
  final header = utf8.encode('// @mgread-plugin-v1 ${base64Url.encode(utf8.encode(_canonicalJson(envelope))).replaceAll('=', '')}\n');
  final bytes = <int>[...header, ...codeBytes];
  return _FixtureArtifact(
    artifact: PluginTransferArtifact(
      bytes: bytes.length,
      developmentFingerprint: null,
      developmentRevision: null,
      format: PluginArtifactFormat.singleFile,
      pluginId: id,
      provenance: PluginArtifactProvenance.installed,
      checksum: _crc32(bytes),
      version: '0.1.2',
    ),
    bytes: bytes,
    version: '0.1.2',
  );
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

const String _embeddedFixtureCode = r'''let c;
export async function activate(x){c=x}
const summary=(id,title)=>({id,title,contentKind:'novel',author:'OHOS Stage 2 fixture',url:`https://example.com/books/${encodeURIComponent(id)}`,coverUrl:c.resource.proxy({kind:'image',url:'https://example.com/favicon.ico',headers:{accept:'image/x-icon'}}),description:'Local OHOS Stage 2 fixture',language:'zh-CN',status:'completed',access:'free',wordCount:32,chapterCount:2,publishedAt:null,updatedAt:'2026-09-19T00:00:00Z',latestChapter:null,categories:['OHOS','ArkWeb'],tags:[],attributes:[]});
const result=t=>({items:[summary(`${c.plugin.id}:book`,t)],nextCursor:null,totalCount:1});
const request=(presentation='hidden')=>({version:1,sessionKey:'ohos-stage2',url:'https://example.com/',method:'GET',headers:{accept:'text/html'},body:null,interaction:'allow',presentation,transport:'html',timeoutMs:30000,maxResponseBytes:65536});
const coordinates=presentation=>({version:1,sessionKey:'ohos-stage2-interaction',url:'https://example.com/',selector:'body',presentation,timeoutMs:30000,action:'coordinates'});
async function cookieJs(){const p=await c.webview.open({visible:false,timeoutMs:30000});try{await p.navigate('https://example.com/',{timeoutMs:30000});await p.executeJavaScript("document.cookie='mgread_stage2=verified; path=/'; true",{timeoutMs:30000});const cookie=await p.executeJavaScript('document.cookie',{timeoutMs:30000});const response=await c.browser.sessionV1.request(request());const html=await p.getHtml({timeoutMs:30000});return `cookie-js:${response.status}:${cookie.includes('mgread_stage2=verified')}:${html.includes('Example Domain')}`}finally{await p.close({timeoutMs:30000})}}
async function javascriptPage(){const p=await c.webview.open({visible:false,timeoutMs:30000});try{await p.navigate('https://example.com/',{timeoutMs:30000});const title=await p.executeJavaScript('return document.title',{timeoutMs:30000});const url=await p.getUrl({timeoutMs:30000});const html=await p.getHtml({timeoutMs:30000});return `js:${title}:${url.startsWith('https://example.com/')}:${html.includes('Example Domain')}`}finally{await p.close({timeoutMs:30000})}}
async function interactionRecovery(){const p=await c.webview.open({visible:false,timeoutMs:30000});await p.navigate('https://example.com/',{timeoutMs:30000});let required=false;try{await c.browser.sessionV1.requestCoordinates(coordinates('hidden'))}catch(e){if(e?.code!=='interaction_required')throw e;required=true}if(!required)throw new Error('hidden interaction did not return interaction_required');await p.show({timeoutMs:30000});try{const accepted=await c.browser.sessionV1.requestCoordinates(coordinates('visible'));return `interaction_required:${accepted.accepted===true}`}finally{await p.hide({timeoutMs:30000});await p.close({timeoutMs:30000})}}
export async function discover(){return {kind:'document',document:{components:[{type:'section',id:`${c.plugin.id}:section`,title:'OHOS Stage 2 fixture',subtitle:null,children:[{type:'contentCollection',id:`${c.plugin.id}:collection`,layout:'list',continuation:null,items:[{content:summary(`${c.plugin.id}:book`,'OHOS Stage 2 fixture'),rank:null,metric:null,recommendation:null}]}]}]}}}
export async function search(r){if(r.query==='cancel'){await new Promise(resolve=>setTimeout(resolve,20000));}if(c.plugin.id.endsWith('cookie-js'))return result(await cookieJs());if(c.plugin.id.endsWith('javascript'))return result(await javascriptPage());if(c.plugin.id.endsWith('interaction')){if(r.query==='interaction-required'){const p=await c.webview.open({visible:false,timeoutMs:30000});await p.navigate('https://example.com/',{timeoutMs:30000});return c.browser.sessionV1.requestCoordinates(coordinates('hidden'))}return result(await interactionRecovery())}return result(`normal:${c.plugin.id}`)}
export async function getDetail(r){return {...summary(r.id,`detail:${c.plugin.id}`),id:r.id,aliases:[],catalogUrl:null}}
export async function getChapters(r){return {items:[0,1].map(order=>({id:`${r.id}:chapter-${order+1}`,title:`Chapter ${order+1}`,order,url:null,volumeTitle:null,wordCount:16,updatedAt:null,isLocked:false,attributes:[]}))}}
export async function getContent(r){return {contentKind:'novel',chapterId:r.chapterId,title:'OHOS Stage 2 fixture content',updatedAt:null,text:`Runtime content path complete: ${r.chapterId}`,pages:[]}}
''';

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

final class _FixtureArtifact {
  const _FixtureArtifact({required this.artifact, required this.bytes, required this.version});

  final PluginTransferArtifact artifact;
  final List<int> bytes;
  final String version;
}
