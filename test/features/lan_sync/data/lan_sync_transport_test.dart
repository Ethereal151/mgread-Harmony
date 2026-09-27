/// 临时扫码同步通过真实 HTTP 服务端/客户端验证，不保留旧 TCP 帧测试。
library;

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/features/lan_sync/data/lan_sync_checksum.dart';
import 'package:mg_read/features/lan_sync/data/lan_sync_transport.dart';
import 'package:mg_read/features/lan_sync/domain/lan_sync_models.dart';

void main() {
  test('LAN transport uses the shared platform identifiers', () {
    expect(lanSyncPlatformIdentifiers, containsAll(<String>['windows', 'macos', 'android', 'ohos']));
    expect(isLanSyncPlatformIdentifier('ohos'), isTrue);
    expect(isLanSyncPlatformIdentifier('linux'), isFalse);
    final expected = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : Platform.isAndroid
        ? 'android'
        : Platform.operatingSystem == 'ohos'
        ? 'ohos'
        : 'unknown';
    expect(lanSyncCurrentPlatformIdentifier, expected);
  });

  test('temporary HTTP sync pairs, reads manifest and transfers selected artifact', () async {
    final bytes = utf8.encode('http artifact');
    final plugin = LanSyncPluginDescriptor(
      id: 'source.http',
      version: '1.0.0',
      bytes: bytes.length,
      artifactFormat: LanSyncPluginArtifactFormat.archive,
      checksum: lanSyncChecksum(bytes),
      transferable: true,
    );
    final sender = await LanSyncSenderService.start(
      manifest: LanSyncManifest(plugins: [plugin], shelfItems: const [], skippedShelfItems: 0),
      openPlugin: (_) async => Stream.value(bytes),
    );
    addTearDown(sender.close);
    final receiver = await LanSyncReceiverConnection.connect(
      LanSyncPeer(
        sessionId: sender.sessionId,
        label: 'sender',
        address: sender.addresses.first,
        port: sender.port,
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      ),
    );
    addTearDown(receiver.close);
    final manifest = await receiver.confirmAndReadManifest();
    expect(manifest.plugins.single.id, plugin.id);
    final received = <int>[];
    final senderDone = sender.events.firstWhere((event) => event is LanSyncSenderDone);
    final importStarted = Completer<void>();
    final releaseImport = Completer<void>();
    final verificationProgress = <List<int>>[];
    final writeProgress = <List<int>>[];
    final receiving = receiver.receivePlugins(
      pluginIds: {plugin.id},
      importPlugin: (_, stream) async {
        received.addAll(await stream.expand((chunk) => chunk).toList());
        importStarted.complete();
        await releaseImport.future;
      },
      onVerificationProgress: (_, completed, total) => verificationProgress.add(<int>[completed, total]),
      onWriteProgress: (_, completed, total) => writeProgress.add(<int>[completed, total]),
    );
    await importStarted.future;
    await senderDone;
    releaseImport.complete();
    await receiving;
    expect(received, bytes);
    expect(verificationProgress.last, <int>[bytes.length, bytes.length]);
    expect(writeProgress.last, <int>[bytes.length, bytes.length]);
  });

  test('address selection excludes virtual interfaces and duplicates', () {
    expect(
      selectLanSyncCandidateAddresses(const [
        LanSyncNetworkAddress(interfaceName: 'Ethernet', address: '192.168.1.8'),
        LanSyncNetworkAddress(interfaceName: 'Ethernet', address: '192.168.1.8'),
        LanSyncNetworkAddress(interfaceName: 'vEthernet (WSL)', address: '172.20.0.1'),
      ]),
      ['192.168.1.8'],
    );
  });

  test('temporary HTTP selection accepts the OHOS receiver platform', () async {
    final bytes = utf8.encode('ohos artifact');
    final plugin = LanSyncPluginDescriptor(
      id: 'source.ohos',
      version: '1.0.0',
      bytes: bytes.length,
      artifactFormat: LanSyncPluginArtifactFormat.archive,
      checksum: lanSyncChecksum(bytes),
      transferable: true,
    );
    final sender = await LanSyncSenderService.start(
      manifest: LanSyncManifest(plugins: [plugin], shelfItems: const [], skippedShelfItems: 0),
      openPlugin: (_) async => Stream.value(bytes),
    );
    addTearDown(sender.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    Future<Map<String, Object?>> post(Uri uri, Map<String, Object?> body, {String? pairingCode}) async {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (pairingCode != null) request.headers.set('x-mgread-session', pairingCode);
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
      final response = await request.close();
      final decoded = jsonDecode(await utf8.decodeStream(response));
      expect(response.statusCode, HttpStatus.ok);
      return (decoded as Map).map<String, Object?>((key, value) => MapEntry(key as String, value));
    }

    final base = Uri.parse('http://${sender.addresses.first}:${sender.port}');
    final pair = await post(base.resolve('/v3/pair'), <String, Object?>{
      'sessionId': sender.sessionId,
      'clientNonce': '01234567890123456789',
    });
    final selection = await post(base.resolve('/v3/selection'), <String, Object?>{
      'pluginIds': [plugin.id],
      'shelfItemIds': const <String>[],
      'platform': 'ohos',
    }, pairingCode: pair['pairingCode'] as String);
    expect((selection['plugins'] as List).single, isA<Map>());

    final invalid = await client.postUrl(base.resolve('/v3/selection'));
    invalid.headers.contentType = ContentType.json;
    invalid.headers.set('x-mgread-session', pair['pairingCode'] as String);
    final invalidBody = utf8.encode(jsonEncode(<String, Object?>{'pluginIds': <String>[], 'shelfItemIds': <String>[]}));
    invalid.contentLength = invalidBody.length;
    invalid.add(invalidBody);
    final invalidResponse = await invalid.close();
    expect(invalidResponse.statusCode, HttpStatus.badRequest);
    await invalidResponse.drain<void>();
  });
}
