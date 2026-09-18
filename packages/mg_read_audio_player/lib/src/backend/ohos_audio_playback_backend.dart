/// OHOS AVPlayer implementation of the audio backend contract.
library;

import 'dart:async';

import 'package:mgread_ohos_media/mgread_ohos_media.dart';

import '../api/audio_contracts.dart';
import '../api/audio_models.dart';

/// Creates a fresh OHOS AVPlayer audio backend.
AudioPlaybackBackend createOhosAudioPlaybackBackend() =>
    OhosAudioPlaybackBackend();

/// Audio backend backed by the OHOS AVPlayer API.
final class OhosAudioPlaybackBackend implements AudioPlaybackBackend {
  OhosAudioPlaybackBackend({OhosMediaClient? client})
    : _client = client ?? OhosMediaClient.instance;

  final OhosMediaClient _client;
  final StreamController<AudioPlaybackBackendSnapshot> _snapshots =
      StreamController<AudioPlaybackBackendSnapshot>.broadcast(sync: true);
  StreamSubscription<OhosMediaEvent>? _events;
  List<AudioTrack> _tracks = const <AudioTrack>[];
  String? _sessionId;
  AudioPlaybackBackendSnapshot _snapshot = const AudioPlaybackBackendSnapshot();
  bool _disposed = false;
  bool _resumeAfterInterruption = false;
  int _generation = 0;

  @override
  AudioPlaybackBackendSnapshot get snapshot => _snapshot;

  @override
  Stream<AudioPlaybackBackendSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> open(
    List<AudioTrack> tracks, {
    required int initialIndex,
    bool play = false,
  }) async {
    _ensureActive();
    if (tracks.isEmpty || initialIndex < 0 || initialIndex >= tracks.length) {
      throw ArgumentError(
        'A non-empty queue and valid initialIndex are required.',
      );
    }
    final generation = ++_generation;
    _tracks = List<AudioTrack>.unmodifiable(tracks);
    await _closeNativeSession();
    if (!_isGenerationCurrent(generation)) return;
    final sessionId = _newSessionId();
    _sessionId = sessionId;
    _snapshot = _snapshot.copyWith(
      currentIndex: initialIndex,
      position: Duration.zero,
      duration: Duration.zero,
      playing: false,
      buffering: true,
      completed: false,
      clearError: true,
    );
    _emit(_snapshot);
    _events = _client.events
        .where((event) => event.sessionId == sessionId)
        .listen((event) => _handleEvent(event, generation));
    try {
      final result = await _client.openAudio(
        sessionId: sessionId,
        uri: _tracks[initialIndex].resource,
        headers: _tracks[initialIndex].httpHeaders,
        initialPosition: Duration.zero,
        play: play,
        trackId: _tracks[initialIndex].id,
        title: _tracks[initialIndex].title,
        artist: _tracks[initialIndex].creator,
        artwork: _tracks[initialIndex].artwork,
      );
      if (!_isCurrent(generation)) return;
      _emit(
        _snapshot.copyWith(
          duration: result.duration ?? _snapshot.duration,
          buffering: false,
          clearError: true,
        ),
      );
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _emit(_snapshot.copyWith(buffering: false, errorMessage: '$error'));
      }
      rethrow;
    }
  }

  @override
  Future<void> append(List<AudioTrack> tracks) async {
    _ensureActive();
    if (tracks.isEmpty) return;
    _tracks = List<AudioTrack>.unmodifiable(<AudioTrack>[
      ..._tracks,
      ...tracks,
    ]);
  }

  @override
  Future<void> play() => _command('play');

  @override
  Future<void> pause() => _command('pause');

  @override
  Future<void> seek(Duration position) => _command(
    'seek',
    arguments: <String, Object?>{
      'positionMs': position.inMilliseconds.clamp(0, 0x7fffffff),
    },
  );

  @override
  Future<void> setRate(double rate) => _command(
    'setRate',
    arguments: <String, Object?>{'rate': rate.clamp(0.5, 3.0)},
  );

  @override
  Future<void> setVolume(double volume) => _command(
    'setVolume',
    arguments: <String, Object?>{'volume': volume.clamp(0.0, 1.0)},
  );

  @override
  Future<void> previous() => _jump(_snapshot.currentIndex - 1);

  @override
  Future<void> next() => _jump(_snapshot.currentIndex + 1);

  @override
  Future<void> jump(int index) => _jump(index);

  Future<void> _jump(int index) async {
    _ensureActive();
    if (index < 0 || index >= _tracks.length) return;
    await open(_tracks, initialIndex: index, play: _snapshot.playing);
  }

  Future<void> _command(
    String method, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    _ensureActive();
    final sessionId = _sessionId;
    if (sessionId == null) throw StateError('No audio episode is open.');
    return _client.command(method, sessionId, arguments: arguments);
  }

  void _handleEvent(OhosMediaEvent event, int generation) {
    if (!_isCurrent(generation)) return;
    final value = event.value;
    final milliseconds = value is num ? value.toInt() : 0;
    switch (event.kind) {
      case 'playing':
        _emit(_snapshot.copyWith(playing: value == true, buffering: false));
      case 'position':
        _emit(
          _snapshot.copyWith(position: Duration(milliseconds: milliseconds)),
        );
      case 'duration':
        _emit(
          _snapshot.copyWith(duration: Duration(milliseconds: milliseconds)),
        );
      case 'buffering':
        _emit(_snapshot.copyWith(buffering: value == true));
      case 'completed':
        _emit(
          _snapshot.copyWith(completed: true, playing: false, buffering: false),
        );
      case 'interrupted':
        if (value == true) {
          _resumeAfterInterruption = _snapshot.playing;
          _emit(_snapshot.copyWith(playing: false, buffering: false));
        } else if (_resumeAfterInterruption) {
          _resumeAfterInterruption = false;
          unawaited(play());
        }
      case 'remoteCommand':
        if (value == 'next') {
          unawaited(next());
        } else if (value == 'previous') {
          unawaited(previous());
        }
      case 'volume':
        _emit(
          _snapshot.copyWith(
            volume: ((value as num?)?.toDouble() ?? 1).clamp(0, 1),
          ),
        );
      case 'rate':
        _emit(
          _snapshot.copyWith(
            rate: (value as num?)?.toDouble() ?? _snapshot.rate,
          ),
        );
      case 'state':
        final state = '$value';
        if (state == 'playing') {
          _emit(_snapshot.copyWith(playing: true, buffering: false));
        } else if (state == 'paused' ||
            state == 'completed' ||
            state == 'stopped') {
          _emit(_snapshot.copyWith(playing: false, buffering: false));
        }
      case 'error':
        _emit(
          _snapshot.copyWith(
            buffering: false,
            errorMessage: event.message ?? 'OHOS 音频播放失败。',
          ),
        );
    }
  }

  Future<void> _closeNativeSession() async {
    final oldSession = _sessionId;
    _sessionId = null;
    await _events?.cancel();
    _events = null;
    if (oldSession != null) await _client.command('dispose', oldSession);
  }

  String _newSessionId() =>
      'ohos-audio-${DateTime.now().microsecondsSinceEpoch}-$_generation';

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation && _sessionId != null;

  bool _isGenerationCurrent(int generation) =>
      !_disposed && generation == _generation;

  void _emit(AudioPlaybackBackendSnapshot value) {
    if (_disposed) return;
    _snapshot = value;
    _snapshots.add(value);
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Audio backend is disposed.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _resumeAfterInterruption = false;
    final sessionId = _sessionId;
    _sessionId = null;
    await _events?.cancel();
    _events = null;
    if (sessionId != null) await _client.command('dispose', sessionId);
    await _snapshots.close();
  }
}
