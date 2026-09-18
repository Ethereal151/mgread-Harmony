import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mgread_ohos_media/mgread_ohos_media.dart';

const _mediaSmokeUrl = String.fromEnvironment('OHOS_MEDIA_SMOKE_URL', defaultValue: 'https://samplelib.com/lib/preview/mp3/sample-3s.mp3');
const _mediaSmokeHoldMs = int.fromEnvironment('OHOS_MEDIA_SMOKE_HOLD_MS', defaultValue: 500);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS AVPlayer opens and controls a short audio track', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;
    final client = OhosMediaClient.instance;
    const sessionId = 'ohos-media-smoke';
    final result = await client.openAudio(
      sessionId: sessionId,
      uri: Uri.parse(_mediaSmokeUrl),
      headers: const <String, String>{},
      initialPosition: Duration.zero,
      play: false,
      trackId: 'smoke-track',
      title: 'MgRead OHOS smoke',
      artist: 'MgRead',
    );
    expect(result.sessionId, sessionId);
    expect(result.duration, isNotNull);

    addTearDown(() => client.command('dispose', sessionId));
    await client.command('setRate', sessionId, arguments: const <String, Object?>{'rate': 1.25});
    await client.command('seek', sessionId, arguments: const <String, Object?>{'positionMs': 0});
    await client.command('play', sessionId);
    await tester.pump(Duration(milliseconds: _mediaSmokeHoldMs < 0 ? 0 : _mediaSmokeHoldMs));
    await client.command('pause', sessionId);
  });
}
