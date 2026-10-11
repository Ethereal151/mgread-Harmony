import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read_audio_player/src/backend/ohos_audio_playback_backend.dart';
import 'package:mg_read_audio_player/src/api/audio_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('mgread/ohos_media');
  const events = EventChannel('mgread/ohos_media/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MockStreamHandlerEventSink? eventSink;
  var playCalls = 0;
  var sessionId = '';

  setUp(() {
    playCalls = 0;
    eventSink = null;
    sessionId = '';
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'audio.open') {
        final arguments = call.arguments as Map<Object?, Object?>;
        sessionId = arguments['sessionId']! as String;
        return <String, Object?>{'sessionId': sessionId, 'durationMs': 1000};
      }
      if (call.method == 'play') playCalls++;
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (_, sink) => eventSink = sink),
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  test(
    'a delayed interruption end cannot resume after an explicit pause',
    () async {
      final backend = OhosAudioPlaybackBackend();
      addTearDown(backend.dispose);
      await backend.open(<AudioTrack>[_track], initialIndex: 0);
      eventSink!.success(_event(sessionId, 'playing', true));
      await Future<void>.delayed(Duration.zero);

      await backend.pause();
      eventSink!.success(_event(sessionId, 'interrupted', true));
      eventSink!.success(_event(sessionId, 'interrupted', false));
      await Future<void>.delayed(Duration.zero);

      expect(playCalls, 0);
    },
  );

  test(
    'an interruption end resumes playback when no pause was requested',
    () async {
      final backend = OhosAudioPlaybackBackend();
      addTearDown(backend.dispose);
      await backend.open(<AudioTrack>[_track], initialIndex: 0);
      eventSink!.success(_event(sessionId, 'playing', true));
      await Future<void>.delayed(Duration.zero);

      eventSink!.success(_event(sessionId, 'interrupted', true));
      eventSink!.success(_event(sessionId, 'interrupted', false));
      await Future<void>.delayed(Duration.zero);

      expect(playCalls, 1);
    },
  );
}

final AudioTrack _track = AudioTrack(
  id: 'track-1',
  title: 'Track 1',
  resource: Uri.parse('https://example.com/track.mp3'),
);

Map<String, Object?> _event(String sessionId, String kind, Object value) =>
    <String, Object?>{'sessionId': sessionId, 'kind': kind, 'value': value};
