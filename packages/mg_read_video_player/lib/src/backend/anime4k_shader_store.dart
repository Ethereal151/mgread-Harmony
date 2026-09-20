/// Materializes the bundled Anime4K GLSL files for native mpv.
///
/// mpv's `glsl-shaders` property accepts filesystem paths. Flutter asset
/// identifiers are not filesystem paths on Android, so the package copies the
/// immutable shader sources into the process temporary directory once and
/// reuses them for subsequent video sessions.
library;

import 'dart:io';

import 'package:flutter/services.dart';

const _anime4kShaderFiles = <String>[
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];

/// Owns the process-local materialized Anime4K asset paths.
final class Anime4KShaderStore {
  /// Prevents construction of the process-wide asset store.
  Anime4KShaderStore._();

  static Future<List<String>>? _paths;

  /// Returns native filesystem paths for the bundled shader chain.
  static Future<List<String>> paths() => _paths ??= _materialize();

  static Future<List<String>> _materialize() async {
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}mg_read_anime4k',
    );
    await directory.create(recursive: true);

    final paths = <String>[];
    for (final name in _anime4kShaderFiles) {
      final asset = await rootBundle.load(
        'packages/mg_read_video_player/assets/anime4k/$name',
      );
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      paths.add(file.path);
    }
    return List<String>.unmodifiable(paths);
  }
}
