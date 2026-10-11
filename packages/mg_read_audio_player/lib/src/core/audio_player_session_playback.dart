/// Intent-aware playback activation and its observable postcondition.
///
/// A transport Future returning only proves that the command was accepted. The
/// session keeps resource loading active until the backend publishes
/// `playing=true`, preventing Android audio focus from being released in the
/// Future/stream race that is more visible in AOT release builds.
part of 'audio_player_session.dart';

extension _AudioPlayerSessionPlayback on AudioPlayerSession {
  Future<bool> _playBackendAndConfirm({
    required int generation,
    required int intentRevision,
    required String? targetTrackId,
    required String failureCode,
    required String failureLocation,
    required String failureMessage,
  }) async {
    if (!_isPlaybackStartCurrent(generation, intentRevision)) return false;
    if (!_snapshot.resourceLoading) {
      _emit(_snapshot.copyWith(resourceLoading: true));
    }
    _recordOperation('trackPlayStarted', targetTrackId: targetTrackId);
    await backend.play();
    _recordOperation('trackPlayReturned', targetTrackId: targetTrackId);

    // The transport Future only means the command was accepted. OHOS can
    // publish playing=true after resource recovery takes longer than the
    // session's stall retry interval, so playback confirmation has no fixed
    // deadline. Backend errors and a newer playback intent still terminate it.
    const pollInterval = Duration(milliseconds: 100);
    while (_isPlaybackStartCurrent(generation, intentRevision)) {
      final backendState = backend.snapshot;
      final backendError = backendState.errorMessage?.trim();
      if (backendError != null && backendError.isNotEmpty) {
        throw AudioPlayerLoadException(
          code: failureCode,
          location: failureLocation,
          message: failureMessage,
          debugDetail: _boundedDebugDetail(backendError),
        );
      }
      if (backendState.playing) {
        _applyReadySnapshot(backendState, resourceLoading: false);
        if (_snapshot.failure?.code == failureCode ||
            _snapshot.failure?.code == 'audio_continuation_failed' ||
            _snapshot.failure?.code == 'audio_recovery_failed' ||
            _snapshot.failure?.code == 'audio_backend_error') {
          _emit(_snapshot.copyWith(clearFailure: true));
        }
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }

  bool _isPlaybackStartCurrent(int generation, int intentRevision) =>
      _isCurrent(generation) &&
      _playbackDesired &&
      intentRevision == _playbackIntentRevision;
}
