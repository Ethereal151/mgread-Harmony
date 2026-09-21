import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:novel_reader_ui/novel_reader_ui.dart';
import 'package:mgread_ohos_media/mgread_ohos_media.dart';

// This small H.264 sample is accepted by the arm64 device media stack used by
// the OHOS acceptance test. Keep the define override for local codec/source
// experiments without making the default smoke test depend on that choice.
const _videoUrl = String.fromEnvironment('OHOS_VIDEO_SMOKE_URL', defaultValue: 'https://www.w3schools.com/html/mov_bbb.mp4');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OHOS AVPlayer video renders a texture and restores the window', (WidgetTester tester) async {
    if (Platform.operatingSystem != 'ohos') return;

    final window = ReaderPlatform.instance;
    await window.setReaderSystemUi(keepScreenOn: true, immersiveMode: false);
    await window.setVideoWindowMode(fullscreen: true);
    addTearDown(() async {
      await window.setVideoWindowMode(fullscreen: false);
      await window.setReaderSystemUi(keepScreenOn: false, immersiveMode: false);
    });

    final client = OhosMediaClient.instance;
    const sessionId = 'ohos-video-smoke';
    final firstFrame = Completer<void>();
    final buffered = Completer<void>();
    final events = <OhosMediaEvent>[];
    final subscription = client.events.where((event) => event.sessionId == sessionId).listen((event) {
      events.add(event);
      if (event.kind == 'firstFrame' && !firstFrame.isCompleted) {
        firstFrame.complete();
      }
      if (event.kind == 'buffered' && event.value is num && !buffered.isCompleted) {
        buffered.complete();
      }
    });
    addTearDown(subscription.cancel);
    addTearDown(() => client.command('dispose', sessionId));

    final opened = await client.openVideo(
      sessionId: sessionId,
      uri: Uri.parse(_videoUrl),
      headers: const <String, String>{},
      initialPosition: Duration.zero,
      play: false,
    );
    expect(opened.sessionId, sessionId);
    expect(opened.textureId, isNotNull);
    expect(opened.duration, isNotNull);
    await tester.pumpWidget(Texture(textureId: opened.textureId!));
    await tester.pump();

    await client.command('setRate', sessionId, arguments: const <String, Object?>{'rate': 1.25});
    await client.command('seek', sessionId, arguments: const <String, Object?>{'positionMs': 0});
    await client.command('play', sessionId);
    await firstFrame.future.timeout(const Duration(seconds: 30));
    await buffered.future.timeout(const Duration(seconds: 30));
    await client.command('pause', sessionId);

    expect(events.any((event) => event.kind == 'playing'), isTrue);
    expect(events.any((event) => event.kind == 'firstFrame'), isTrue);
    final bufferedEvent = events.lastWhere((event) => event.kind == 'buffered');
    expect(bufferedEvent.value, isA<num>());
    expect((bufferedEvent.value! as num).toDouble(), greaterThanOrEqualTo(0));
    await client.command('dispose', sessionId);
    await tester.pump(const Duration(milliseconds: 200));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
