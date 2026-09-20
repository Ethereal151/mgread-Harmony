/// Best-effort terminal cleanup for an unmounted video session.
///
/// Responsibilities:
/// - Serialize the final progress write behind every earlier queued save.
/// - Start backend cleanup immediately, independently of slow persistence.
///
/// Notes:
/// - Errors cannot be surfaced into the disposed widget tree and are isolated.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/contracts.dart';
import '../api/models.dart';

/// Whether a platform lifecycle transition requires an immediate pause.
///
/// Desktop video playback is allowed to continue while a Windows or macOS
/// window is inactive, hidden or paused. Detached views still stop playback
/// on every platform because the view is no longer attached to the engine.
bool pausesVideoForLifecycle(
  AppLifecycleState state, {
  TargetPlatform? platform,
}) {
  if (state == AppLifecycleState.detached) return true;
  if (_platformIsDesktop(platform)) return false;
  return state == AppLifecycleState.inactive ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden;
}

/// Whether playback commands may run in the given lifecycle state.
bool allowsVideoPlaybackForLifecycle(
  AppLifecycleState state, {
  TargetPlatform? platform,
}) => !pausesVideoForLifecycle(state, platform: platform);

bool _platformIsDesktop(TargetPlatform? platform) {
  final targetPlatform = platform ?? defaultTargetPlatform;
  return targetPlatform == TargetPlatform.windows ||
      targetPlatform == TargetPlatform.macOS;
}

/// Completes persistence and backend cleanup after the view has detached.
Future<void> shutdownVideoSession({
  required VideoPlaybackBackend backend,
  required VideoPlaybackStateStore store,
  required Future<void> saveTail,
  required VideoPlaybackProgress? progress,
}) async {
  final cleanup = _cleanupBackend(backend);
  await _persistFinalProgress(
    store: store,
    saveTail: saveTail,
    progress: progress,
  );
  await cleanup;
}

Future<void> _persistFinalProgress({
  required VideoPlaybackStateStore store,
  required Future<void> saveTail,
  required VideoPlaybackProgress? progress,
}) async {
  try {
    await saveTail;
  } on Object {
    // A final save is still attempted after an older failed write.
  }
  if (progress != null) {
    try {
      await store.save(progress);
    } on Object {
      // Disposal cannot surface persistence errors into a dead widget tree.
    }
  }
}

Future<void> _cleanupBackend(VideoPlaybackBackend backend) async {
  try {
    await backend.pause();
  } on Object {
    // Disposal must continue when pause is unsupported or already detached.
  }
  try {
    await backend.dispose();
  } on Object {
    // Native cleanup failures cannot be recovered after route disposal.
  }
}
