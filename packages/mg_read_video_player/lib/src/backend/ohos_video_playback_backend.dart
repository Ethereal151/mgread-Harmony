/// OHOS AVPlayer implementation of the video backend contract.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mgread_ohos_media/mgread_ohos_media.dart';

import '../api/contracts.dart';
import '../api/models.dart';

/// Creates a fresh OHOS AVPlayer video backend.
VideoPlaybackBackend createOhosVideoPlaybackBackend() =>
    OhosVideoPlaybackBackend();

/// Video backend that renders through a Flutter texture owned by AVPlayer.
final class OhosVideoPlaybackBackend implements VideoPlaybackBackend {
  /// Creates an OHOS backend using the process-scoped media channel.
  OhosVideoPlaybackBackend({OhosMediaClient? client})
    : _client = client ?? OhosMediaClient.instance;

  final OhosMediaClient _client;
  final ValueNotifier<VideoPlaybackBackendState> _state =
      ValueNotifier<VideoPlaybackBackendState>(
        const VideoPlaybackBackendState(),
      );
  StreamSubscription<OhosMediaEvent>? _events;
  String? _sessionId;
  int? _textureId;
  Map<String, Object?>? _webViewParams;
  bool _webViewPlayback = false;
  int _generation = 0;
  // ignore: prefer_final_fields
  double _rate = 1;
  // ignore: prefer_final_fields
  double _volume = 100;
  bool _disposed = false;

  @override
  ValueListenable<VideoPlaybackBackendState> get state => _state;

  @override
  Widget buildSurface({required BoxFit fit, Key? key}) {
    final webViewParams = _webViewParams;
    if (webViewParams != null) {
      return _NativeOhosView(
        key: key,
        viewType: 'mgread_ohos_hls_video',
        creationParams: webViewParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      );
    }
    final textureId = _textureId;
    return textureId == null
        ? SizedBox.expand(key: key)
        : KeyedSubtree(
            key: key,
            child: Texture(key: ValueKey<int>(textureId), textureId: textureId),
          );
  }

  @override
  Future<void> open(
    VideoEpisode episode, {
    required Duration initialPosition,
    required bool play,
  }) async {
    _ensureActive();
    final uri = episode.uri;
    if (uri == null) {
      throw StateError('The selected video episode has no playback resource.');
    }
    final generation = ++_generation;
    _emit(
      VideoPlaybackBackendState(
        duration: episode.durationHint ?? Duration.zero,
        rate: _rate,
        volume: _volume,
        buffering: true,
      ),
    );
    await _closeNativeSession();
    if (!_isGenerationCurrent(generation)) return;
    final sessionId = _newSessionId();
    _sessionId = sessionId;
    if (Platform.operatingSystem == 'ohos' &&
        episode.resourceType == VideoEpisodeResourceType.hls) {
      _webViewPlayback = true;
      _webViewParams = <String, Object?>{'sessionId': sessionId, 'url': uri};
      _emit(
        _state.value.copyWith(
          buffering: false,
          firstFrameReady: true,
          playing: play,
          clearError: true,
        ),
      );
      return;
    }
    _events = _client.events
        .where((event) => event.sessionId == sessionId)
        .listen((event) => _handleEvent(event, generation));
    try {
      // AVPlayer can prepare a native surface before Flutter has rebuilt the
      // Texture widget. Starting here makes API 26 devices occasionally
      // deliver the first frame to an unconsumed surface; the engine then
      // reports SurfaceFrame::Submit failed and no firstFrame event arrives.
      // Keep open paused until the texture is mounted below, then start it
      // through the normal command path.
      final result = await _client.openVideo(
        sessionId: sessionId,
        uri: Uri.parse(uri),
        headers: episode.httpHeaders,
        resourceType: episode.resourceType.name,
        initialPosition: initialPosition,
        play: false,
      );
      if (!_isCurrent(generation)) return;
      _textureId = result.textureId;
      _emit(
        _state.value.copyWith(
          duration: result.duration ?? _state.value.duration,
          buffering: false,
          clearError: true,
        ),
      );
      if (play) {
        // Wait for the state emission above to rebuild Texture before AVPlayer
        // is allowed to produce the first frame.
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrent(generation)) return;
        await _client.command('play', sessionId);
      }
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _emit(
          _state.value.copyWith(
            buffering: false,
            errorMessage: '$error',
            errorKind: VideoPlaybackBackendErrorKind.unknown,
          ),
        );
      }
      rethrow;
    }
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
  )..then<void>((_) => _rate = rate.clamp(0.5, 3.0));

  @override
  Future<void> setVolume(double volume) => _command(
    'setVolume',
    arguments: <String, Object?>{'volume': (volume / 100).clamp(0.0, 1.0)},
  )..then<void>((_) => _volume = volume.clamp(0.0, 100.0));

  Future<void> _command(
    String method, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    _ensureActive();
    final sessionId = _sessionId;
    if (sessionId == null) throw StateError('No video episode is open.');
    if (_webViewPlayback) {
      return _client.webCommand(method, sessionId, arguments: arguments);
    }
    return _client.command(method, sessionId, arguments: arguments);
  }

  void _handleEvent(OhosMediaEvent event, int generation) {
    if (!_isGenerationCurrent(generation)) return;
    final value = event.value;
    final milliseconds = value is num ? value.toInt() : 0;
    switch (event.kind) {
      case 'playing':
        _emit(_state.value.copyWith(playing: value == true, buffering: false));
      case 'position':
        _emit(
          _state.value.copyWith(position: Duration(milliseconds: milliseconds)),
        );
      case 'duration':
        _emit(
          _state.value.copyWith(duration: Duration(milliseconds: milliseconds)),
        );
      case 'buffering':
        _emit(_state.value.copyWith(buffering: value == true));
      case 'buffered':
        _emit(
          _state.value.copyWith(
            bufferedPosition: Duration(milliseconds: milliseconds),
          ),
        );
      case 'bufferingPercent':
        // OHOS reports a percentage separately from the playable duration.
        // Keep the last duration-based position until a duration estimate is
        // available; the buffering flag remains the authoritative state.
        break;
      case 'completed':
        _emit(
          _state.value.copyWith(
            completed: true,
            playing: false,
            buffering: false,
          ),
        );
      case 'interrupted':
        if (value == true) {
          _emit(_state.value.copyWith(playing: false, buffering: false));
        }
      case 'firstFrame':
        _emit(_state.value.copyWith(firstFrameReady: true, buffering: false));
      case 'volume':
        _emit(
          _state.value.copyWith(
            volume: ((value as num?)?.toDouble() ?? 1) * 100,
          ),
        );
      case 'rate':
        _emit(
          _state.value.copyWith(rate: (value as num?)?.toDouble() ?? _rate),
        );
      case 'state':
        final state = '$value';
        if (state == 'playing') {
          _emit(_state.value.copyWith(playing: true, buffering: false));
        } else if (state == 'paused' ||
            state == 'completed' ||
            state == 'stopped') {
          _emit(_state.value.copyWith(playing: false, buffering: false));
        }
      case 'error':
        _emit(
          _state.value.copyWith(
            buffering: false,
            errorMessage: event.message ?? 'OHOS 视频播放失败。',
            errorKind: VideoPlaybackBackendErrorKind.unknown,
          ),
        );
    }
  }

  Future<void> _closeNativeSession() async {
    final sessionId = _sessionId;
    _sessionId = null;
    _textureId = null;
    final webSessionId = _webViewPlayback ? sessionId : null;
    _webViewPlayback = false;
    _webViewParams = null;
    await _events?.cancel();
    _events = null;
    if (webSessionId != null) {
      await _client.webCommand('dispose', webSessionId);
    } else if (sessionId != null) {
      await _client.command('dispose', sessionId);
    }
  }

  String _newSessionId() =>
      'ohos-video-${DateTime.now().microsecondsSinceEpoch}-$_generation';

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation && _sessionId != null;

  bool _isGenerationCurrent(int generation) =>
      !_disposed && generation == _generation;

  void _emit(VideoPlaybackBackendState value) {
    if (_disposed) return;
    _state.value = value;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Video backend is disposed.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final sessionId = _sessionId;
    _sessionId = null;
    _textureId = null;
    final webSessionId = _webViewPlayback ? sessionId : null;
    _webViewPlayback = false;
    _webViewParams = null;
    await _events?.cancel();
    _events = null;
    if (webSessionId != null) {
      await _client.webCommand('dispose', webSessionId);
    } else if (sessionId != null) {
      await _client.command('dispose', sessionId);
    }
    _state.dispose();
  }
}

/// Embeds the HLS ArkWeb view through OHOS native view composition.
///
/// The regular [OhosView] uses the texture path. On the affected API 26
/// devices that path leaves the native Web node below Flutter's main
/// XComponent, even though ArkWeb is decoding frames successfully. Surface
/// composition lets the system place the video view in the visible native
/// hierarchy instead of placing it behind Flutter's XComponent.
final class _NativeOhosView extends StatefulWidget {
  const _NativeOhosView({
    super.key,
    required this.viewType,
    required this.creationParams,
    required this.creationParamsCodec,
    required this.hitTestBehavior,
  });

  final String viewType;
  final Object? creationParams;
  final MessageCodec<Object?> creationParamsCodec;
  final PlatformViewHitTestBehavior hitTestBehavior;

  @override
  State<_NativeOhosView> createState() => _NativeOhosViewState();
}

final class _NativeOhosViewState extends State<_NativeOhosView> {
  ExpensiveOhosViewController? _controller;
  TextDirection? _layoutDirection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final direction = Directionality.of(context);
    if (_controller == null) {
      _layoutDirection = direction;
      _controller = PlatformViewsService.initExpensiveOhosView(
        id: platformViewsRegistry.getNextPlatformViewId(),
        viewType: widget.viewType,
        layoutDirection: direction,
        creationParams: widget.creationParams,
        creationParamsCodec: widget.creationParamsCodec,
      );
      // Expensive OHOS views do not wait for a size like texture views do.
      // OhosViewSurface only supplies the compositor surface; the controller
      // still has to be explicitly created before the native ArkWeb factory
      // can mount its Web component.
      unawaited(_controller!.create());
    } else if (_layoutDirection != direction) {
      _layoutDirection = direction;
      _controller!.setLayoutDirection(direction);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.expand();
    }
    return Focus(
      child: OhosViewSurface(
        controller: controller,
        hitTestBehavior: widget.hitTestBehavior,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
    );
  }
}
