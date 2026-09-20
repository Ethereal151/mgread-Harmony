import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read_video_player/mg_read_video_player.dart';

import 'package:mg_read/app/source_verification_video_probe_surface.dart';
import 'package:mg_read/features/plugins/application/source_verification.dart';

void main() {
  testWidgets('requires a real first frame and advancing muted playback', (tester) async {
    final controller = SourceVerificationVideoPlaybackProbeController();
    final backend = _ProbeBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 135,
          child: SourceVerificationVideoPlaybackProbeSurface(controller: controller, backendFactory: () => backend),
        ),
      ),
    );

    final outcomeFuture = controller.probe(
      SourceVerificationVideoPlaybackRequest(
        uri: Uri.parse('https://media.example/video.m3u8'),
        headers: const <String, String>{'Referer': 'https://source.example/'},
        timeout: const Duration(seconds: 1),
      ),
    );
    await tester.pump();
    final outcome = await outcomeFuture;

    expect(outcome.passed, isTrue);
    expect(outcome.firstFrameReady, isTrue);
    expect(outcome.position, const Duration(milliseconds: 500));
    expect(backend.volume, 0);
    expect(backend.openedEpisode?.httpHeaders, const <String, String>{'Referer': 'https://source.example/'});
  });

  testWidgets('preserves the backend failure classification', (tester) async {
    final controller = SourceVerificationVideoPlaybackProbeController();
    final backend = _ProbeBackend(errorKind: VideoPlaybackBackendErrorKind.runtimeResourceUnavailable);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 135,
          child: SourceVerificationVideoPlaybackProbeSurface(controller: controller, backendFactory: () => backend),
        ),
      ),
    );

    final outcomeFuture = controller.probe(
      SourceVerificationVideoPlaybackRequest(
        uri: Uri.parse('http://127.0.0.1:1234/source-resource'),
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
      ),
    );
    await tester.pump();
    final outcome = await outcomeFuture;

    expect(outcome.passed, isFalse);
    expect(outcome.code, 'video_runtime_resource_unavailable');
    expect(outcome.errorKind, 'runtimeResourceUnavailable');
  });

  testWidgets('classifies production backend initialization failures', (tester) async {
    final controller = SourceVerificationVideoPlaybackProbeController();
    await tester.pumpWidget(
      MaterialApp(
        home: SourceVerificationVideoPlaybackProbeSurface(
          controller: controller,
          backendFactory: () => throw StateError('native runtime unavailable'),
        ),
      ),
    );

    final outcome = await controller.probe(
      SourceVerificationVideoPlaybackRequest(
        uri: Uri.parse('https://media.example/video.m3u8'),
        headers: const <String, String>{},
        timeout: const Duration(seconds: 1),
      ),
    );

    expect(outcome.passed, isFalse);
    expect(outcome.code, 'video_backend_initialization_failed');
    expect(outcome.errorKind, 'StateError');
  });
}

final class _ProbeBackend implements VideoPlaybackBackend {
  _ProbeBackend({this.errorKind});

  final VideoPlaybackBackendErrorKind? errorKind;
  final ValueNotifier<VideoPlaybackBackendState> _state = ValueNotifier<VideoPlaybackBackendState>(const VideoPlaybackBackendState());
  VideoEpisode? openedEpisode;
  double? volume;

  @override
  ValueListenable<VideoPlaybackBackendState> get state => _state;

  @override
  Widget buildSurface({required BoxFit fit, Key? key}) => SizedBox(key: key);

  @override
  Future<void> open(VideoEpisode episode, {required Duration initialPosition, required bool play}) async {
    openedEpisode = episode;
    _state.value = const VideoPlaybackBackendState(buffering: true);
  }

  @override
  Future<void> play() async {
    final failure = errorKind;
    if (failure != null) {
      _state.value = VideoPlaybackBackendState(errorKind: failure, errorMessage: 'Safe playback failure.');
      return;
    }
    _state.value = const VideoPlaybackBackendState(
      playing: true,
      firstFrameReady: true,
      position: Duration(milliseconds: 500),
      duration: Duration(minutes: 1),
      bufferedPosition: Duration(seconds: 5),
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> dispose() async {
    _state.dispose();
  }
}
