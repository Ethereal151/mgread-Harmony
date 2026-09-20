import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read_video_player/src/backend/anime4k_shader_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('materializes the bundled Anime4K fast shader chain', () async {
    final paths = await Anime4KShaderStore.paths();

    expect(paths, hasLength(6));
    for (final path in paths) {
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));
    }
  });
}
