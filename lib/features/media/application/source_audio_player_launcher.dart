/// Source-audio launcher for the app-global playback host.
///
/// Responsibilities:
/// - Hand one selected source chapter to the process-scoped playback service.
/// - Keep navigation free to return while the root host retains playback.
///
/// Notes:
/// - The service replaces an older audio session before opening a new one.
/// - Runtime media resources remain memory-only inside the active request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

import 'package:mg_read/features/discovery/application/source_content_cover_handoff.dart';
import 'package:mg_read/features/media/application/source_audio_playback_service.dart';
import 'package:mg_read/shared/presentation/widgets/async_book_cover_loader.dart';

/// Opens an audio chapter in the app-root player and completes when it stops.
Future<void> openTransientSourceAudioPlayer(
  BuildContext context, {
  required NavigatorState navigator,
  required PluginContentDetail detail,
  required PluginChaptersResult firstCatalogPage,
  required PluginChapterSummary chapter,
  required String pluginVersion,
  String? libraryItemId,
}) async {
  if (!navigator.mounted) return Future<void>.value();
  final container = ProviderScope.containerOf(context, listen: false);
  final preparedDetail = await _prepareAudioDetailCover(container, detail: detail, pluginVersion: pluginVersion);
  if (!navigator.mounted) return;
  await container
      .read(sourceAudioPlaybackServiceProvider.notifier)
      .open(
        SourceAudioPlaybackRequest(
          detail: preparedDetail,
          firstCatalogPage: firstCatalogPage,
          chapter: chapter,
          libraryItemId: libraryItemId,
          pluginVersion: pluginVersion,
        ),
      );
}

Future<PluginContentDetail> _prepareAudioDetailCover(
  ProviderContainer container, {
  required PluginContentDetail detail,
  required String pluginVersion,
}) async {
  final summary = detail.summary;
  if (summary.coverBytes?.isNotEmpty == true || summary.coverUrl == null) {
    return detail;
  }
  final request = BookCoverRequest(
    pluginId: detail.pluginId,
    pluginVersion: pluginVersion,
    remoteContentId: summary.id,
    coverUrl: summary.coverUrl!,
  );
  try {
    final bytes = await container.read(bookCoverBytesProvider(request).future);
    if (bytes == null || bytes.isEmpty) return detail;
    return preserveSourceContentCover(detail: detail, resolvedCoverBytes: bytes);
  } on Object {
    return detail;
  }
}
