/// 数据源 CLI 的生产视频播放探针表面。
///
/// 职责：挂载真实 MediaKit 视频表面，静音打开选集，并等待首帧、播放状态和进度推进后返回安全结果。
/// 注意：每个样本使用全新 backend；原始 URL、headers 和原生播放器错误不会写入稳定报告。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_read_video_player/mg_read_video_player.dart';

import 'package:mg_read/features/plugins/application/source_verification.dart';

typedef SourceVerificationVideoPlaybackBackendFactory = VideoPlaybackBackend Function();

/// Serial bridge used by the verification engine after this surface is mounted.
final class SourceVerificationVideoPlaybackProbeController implements SourceVerificationVideoPlaybackProbe {
  Future<SourceVerificationVideoPlaybackProbeResult> Function(SourceVerificationVideoPlaybackRequest request)? _handler;
  Future<void> _queue = Future<void>.value();

  bool get isAttached => _handler != null;

  @override
  Future<SourceVerificationVideoPlaybackProbeResult> probe(SourceVerificationVideoPlaybackRequest request) {
    final completer = Completer<SourceVerificationVideoPlaybackProbeResult>();
    final operation = _queue.then<void>((_) async {
      final handler = _handler;
      if (handler == null) {
        completer.complete(
          const SourceVerificationVideoPlaybackProbeResult(
            passed: false,
            code: 'video_probe_unavailable',
            elapsed: Duration.zero,
            firstFrameReady: false,
            playing: false,
            buffering: false,
            position: Duration.zero,
            duration: Duration.zero,
            bufferedPosition: Duration.zero,
          ),
        );
        return;
      }
      try {
        completer.complete(await handler(request));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return completer.future;
  }

  void attach(Future<SourceVerificationVideoPlaybackProbeResult> Function(SourceVerificationVideoPlaybackRequest request) handler) {
    _handler = handler;
  }

  void detach() => _handler = null;
}

/// A real, painted video surface used only by desktop source-check CLI mode.
final class SourceVerificationVideoPlaybackProbeSurface extends StatefulWidget {
  const SourceVerificationVideoPlaybackProbeSurface({required this.controller, required this.backendFactory, super.key});

  final SourceVerificationVideoPlaybackProbeController controller;
  final SourceVerificationVideoPlaybackBackendFactory backendFactory;

  @override
  State<SourceVerificationVideoPlaybackProbeSurface> createState() => _SourceVerificationVideoPlaybackProbeSurfaceState();
}

final class _SourceVerificationVideoPlaybackProbeSurfaceState extends State<SourceVerificationVideoPlaybackProbeSurface> {
  VideoPlaybackBackend? _backend;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.attach(_probe);
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: backend == null ? const SizedBox.expand() : backend.buildSurface(fit: BoxFit.contain, key: ValueKey<int>(_generation)),
      ),
    );
  }

  Future<SourceVerificationVideoPlaybackProbeResult> _probe(SourceVerificationVideoPlaybackRequest request) async {
    final stopwatch = Stopwatch()..start();
    late final VideoPlaybackBackend backend;
    try {
      backend = await _replaceBackend();
    } on Object catch (error) {
      return SourceVerificationVideoPlaybackProbeResult(
        passed: false,
        code: 'video_backend_initialization_failed',
        elapsed: stopwatch.elapsed,
        firstFrameReady: false,
        playing: false,
        buffering: false,
        position: Duration.zero,
        duration: Duration.zero,
        bufferedPosition: Duration.zero,
        errorKind: error.runtimeType.toString(),
        errorMessage: 'The production video backend could not be initialized.',
      );
    }
    final completer = Completer<SourceVerificationVideoPlaybackProbeResult>();

    SourceVerificationVideoPlaybackProbeResult snapshot({
      required bool passed,
      required String code,
      VideoPlaybackBackendState? state,
      String? errorKind,
      String? errorMessage,
    }) {
      final current = state ?? backend.state.value;
      return SourceVerificationVideoPlaybackProbeResult(
        passed: passed,
        code: code,
        elapsed: stopwatch.elapsed,
        firstFrameReady: current.firstFrameReady,
        playing: current.playing,
        buffering: current.buffering,
        position: current.position,
        duration: current.duration,
        bufferedPosition: current.bufferedPosition,
        errorKind: errorKind ?? current.errorKind?.name,
        errorMessage: errorMessage ?? current.errorMessage,
      );
    }

    void inspect() {
      if (completer.isCompleted) return;
      final state = backend.state.value;
      if (state.errorMessage?.trim().isNotEmpty ?? false) {
        completer.complete(
          snapshot(
            passed: false,
            code: switch (state.errorKind) {
              VideoPlaybackBackendErrorKind.proxyUnavailable => 'video_proxy_unavailable',
              VideoPlaybackBackendErrorKind.runtimeResourceUnavailable => 'video_runtime_resource_unavailable',
              _ => 'video_stream_error',
            },
            state: state,
          ),
        );
        return;
      }
      if (state.firstFrameReady && state.playing && state.position > Duration.zero) {
        completer.complete(snapshot(passed: true, code: 'video_playback_ready', state: state));
      }
    }

    backend.state.addListener(inspect);
    unawaited(() async {
      try {
        await backend.open(
          VideoEpisode(id: 'source-check', title: 'source-check', uri: request.uri.toString(), httpHeaders: request.headers),
          initialPosition: Duration.zero,
          play: false,
        );
        await backend.setVolume(0);
        await backend.play();
        inspect();
      } on Object catch (error) {
        if (!completer.isCompleted) {
          completer.complete(
            snapshot(
              passed: false,
              code: 'video_backend_open_failed',
              errorKind: error.runtimeType.toString(),
              errorMessage: 'The production video backend could not open the media.',
            ),
          );
        }
      }
    }());

    try {
      return await completer.future.timeout(
        request.timeout,
        onTimeout: () => snapshot(
          passed: false,
          code: 'video_first_frame_timeout',
          errorMessage: 'The production video backend did not render and advance before the timeout.',
        ),
      );
    } finally {
      backend.state.removeListener(inspect);
      try {
        await backend.pause();
      } on Object {
        // The failure result above remains authoritative when pause is unavailable.
      }
      await backend.dispose();
      if (mounted && identical(_backend, backend)) {
        setState(() => _backend = null);
      }
    }
  }

  Future<VideoPlaybackBackend> _replaceBackend() async {
    final previous = _backend;
    final next = widget.backendFactory();
    if (!mounted) {
      await next.dispose();
      throw StateError('The video verification surface is not mounted.');
    }
    setState(() {
      _backend = next;
      _generation += 1;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (previous != null) await previous.dispose();
    return next;
  }

  @override
  void dispose() {
    widget.controller.detach();
    final backend = _backend;
    if (backend != null) unawaited(backend.dispose());
    super.dispose();
  }
}
