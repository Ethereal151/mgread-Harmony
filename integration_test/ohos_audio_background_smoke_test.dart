import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_media/mgread_ohos_media.dart';

const _backgroundHoldMs = int.fromEnvironment('OHOS_AUDIO_BACKGROUND_HOLD_MS', defaultValue: 10000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS AVSession keeps audio position advancing while the app is backgrounded', (tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    final client = OhosMediaClient.instance;
    const sessionId = 'ohos-audio-background-smoke';
    final positions = <int>[];
    final subscription = client.events.where((event) => event.sessionId == sessionId && event.kind == 'position').listen((event) {
      if (event.value is num) positions.add((event.value! as num).toInt());
    });
    addTearDown(() async {
      await subscription.cancel();
      await client.command('dispose', sessionId);
    });

    await client.openAudio(
      sessionId: sessionId,
      uri: Uri.parse('https://samplelib.com/lib/preview/mp3/sample-6s.mp3'),
      headers: const <String, String>{},
      initialPosition: Duration.zero,
      play: true,
      trackId: 'background-smoke-track',
      title: 'MgRead background smoke',
      artist: 'MgRead',
    );
    debugPrint('OHOS_AUDIO_BACKGROUND_READY=true');
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(Duration(milliseconds: _backgroundHoldMs < 0 ? 0 : _backgroundHoldMs));
    debugPrint('OHOS_AUDIO_BACKGROUND_MAX_POSITION=${positions.isEmpty ? 0 : positions.reduce((a, b) => a > b ? a : b)}');
    expect(positions.any((position) => position > 0), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
